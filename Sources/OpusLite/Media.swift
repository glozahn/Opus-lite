import AVFoundation
import AppKit
import PDFKit
import Vision

/// Media helpers: duration, audio from video, waveform and OCR.
enum Media {
    static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpusLite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Metadata

    static func duration(of url: URL, kind: FileKind) async -> TimeInterval {
        switch kind {
        case .audio:
            if let file = try? AVAudioFile(forReading: url) {
                return Double(file.length) / file.fileFormat.sampleRate
            }
            fallthrough
        case .video:
            let asset = AVURLAsset(url: url)
            return (try? await asset.load(.duration).seconds) ?? 0
        case .pdf, .image:
            return 0
        }
    }

    static func pageCount(of url: URL, kind: FileKind) -> Int {
        switch kind {
        case .pdf: PDFDocument(url: url)?.pageCount ?? 0
        case .image: 1
        default: 0
        }
    }

    // MARK: - Playable / transcribable audio

    /// An audio path AVAudioFile can read. Videos are extracted to .m4a (cached).
    static func playableAudio(for item: LibraryItem) async throws -> URL {
        guard item.kind == .video else { return item.url }
        let out = cacheDir.appendingPathComponent(item.id.uuidString).appendingPathExtension("m4a")
        if FileManager.default.fileExists(atPath: out.path) { return out }

        let asset = AVURLAsset(url: item.url)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw TranscriptionError.noAudioTrack
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.noAudioTrack
        }
        let tmp = out.deletingPathExtension().appendingPathExtension("part.m4a")
        try? FileManager.default.removeItem(at: tmp)
        try await session.export(to: tmp, as: .m4a)
        try FileManager.default.moveItem(at: tmp, to: out)
        return out
    }

    // MARK: - Waveform

    /// Normalized peaks (0…1) in `bins` columns.
    static func waveform(of url: URL, bins: Int = 180) async -> [Float] {
        await Task.detached(priority: .utility) {
            guard let file = try? AVAudioFile(forReading: url), file.length > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1 << 15)
            else { return [] }
            let perBin = max(Int(file.length) / bins, 1)
            var peaks = [Float](repeating: 0, count: bins)
            var frame = 0
            while file.framePosition < file.length {
                do { try file.read(into: buffer) } catch { break }
                let n = Int(buffer.frameLength)
                if n == 0 { break }
                guard let data = buffer.floatChannelData?[0] else { break }
                // Stride through samples so long audio stays cheap.
                var i = 0
                while i < n {
                    let bin = min((frame + i) / perBin, bins - 1)
                    peaks[bin] = max(peaks[bin], abs(data[i]))
                    i += 8
                }
                frame += n
            }
            let top = max(peaks.max() ?? 1, 0.001)
            return peaks.map { sqrt($0 / top) }
        }.value
    }

    // MARK: - OCR

    /// Text per page: uses the PDF text layer when present and OCR (Vision) otherwise.
    static func recognizeText(
        in item: LibraryItem,
        languages: [String],
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> [Segment] {
        switch item.kind {
        case .image:
            guard let image = NSImage(contentsOf: item.url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return []
            }
            let text = try await ocr(image, languages: languages)
            await progress(1)
            return text.isEmpty ? [] : [Segment(start: 0, end: 0, text: text)]

        case .pdf:
            guard let doc = PDFDocument(url: item.url) else { return [] }
            var out: [Segment] = []
            for index in 0..<doc.pageCount {
                try Task.checkCancellation()
                guard let page = doc.page(at: index) else { continue }
                var text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.count < 20, let image = render(page) {
                    text = try await ocr(image, languages: languages)
                }
                if !text.isEmpty {
                    out.append(Segment(start: Double(index), end: Double(index + 1), text: text))
                }
                await progress(Double(index + 1) / Double(doc.pageCount))
            }
            return out

        default:
            return []
        }
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = 2000 / max(bounds.width, bounds.height, 1)
        let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func ocr(_ image: CGImage, languages: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}
