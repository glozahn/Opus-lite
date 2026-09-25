import AVFoundation
import Speech

/// Motores de transcripción. Todos corren en el Mac y usan modelos del sistema:
/// la app no incluye pesos propios.
enum Engine: String, CaseIterable, Identifiable, Codable, Sendable {
    case speech, dictation, legacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speech: "SpeechAnalyzer"
        case .dictation: "Dictado"
        case .legacy: "SFSpeech clásico"
        }
    }

    var detail: String {
        switch self {
        case .speech: "El más rápido y preciso. Recomendado."
        case .dictation: "Modelo de dictado; buena puntuación."
        case .legacy: "Reconocedor anterior. Más lento, respaldo."
        }
    }
}

enum TranscriptionError: LocalizedError {
    case unsupportedLocale(String)
    case notAuthorized
    case recognizerUnavailable
    case noAudioTrack

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let id): "El idioma \(id) no está disponible para este motor."
        case .notAuthorized: "Permiso de reconocimiento de voz denegado (Ajustes del Sistema › Privacidad)."
        case .recognizerUnavailable: "El reconocedor no está disponible ahora mismo."
        case .noAudioTrack: "El archivo no tiene pista de audio."
        }
    }
}

enum Transcriber {
    typealias Progress = @Sendable (Double) async -> Void
    typealias Partial = @Sendable ([Segment]) async -> Void

    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted { $0.identifier < $1.identifier }
    }

    static func installedLocales() async -> Set<String> {
        Set(await SpeechTranscriber.installedLocales.map(\.identifier))
    }

    /// Descarga (si falta) el modelo de idioma del sistema.
    static func installModel(for locale: Locale, progress: Progress? = nil) async throws {
        guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.unsupportedLocale(locale.identifier)
        }
        let module = SpeechTranscriber(locale: loc, preset: .transcription)
        try await install(module, progress: progress)
    }

    /// Transcribe el audio de `url` en segmentos con tiempos.
    static func run(
        url: URL,
        duration: TimeInterval,
        engine: Engine,
        locale: Locale,
        progress: @escaping Progress,
        partial: @escaping Partial
    ) async throws -> [Segment] {
        switch engine {
        case .speech:
            guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                throw TranscriptionError.unsupportedLocale(locale.identifier)
            }
            let module = SpeechTranscriber(
                locale: loc, transcriptionOptions: [],
                reportingOptions: [.volatileResults], attributeOptions: []
            )
            return try await analyze(url: url, duration: duration, module: module, progress: progress, partial: partial) {
                module.results.map { Chunk(text: String($0.text.characters), range: $0.range, isFinal: $0.isFinal) }
            }

        case .dictation:
            guard let loc = await DictationTranscriber.supportedLocale(equivalentTo: locale) else {
                throw TranscriptionError.unsupportedLocale(locale.identifier)
            }
            let module = DictationTranscriber(
                locale: loc, contentHints: [], transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults], attributeOptions: []
            )
            return try await analyze(url: url, duration: duration, module: module, progress: progress, partial: partial) {
                module.results.map { Chunk(text: String($0.text.characters), range: $0.range, isFinal: $0.isFinal) }
            }

        case .legacy:
            return try await legacy(url: url, duration: duration, locale: locale, progress: progress, partial: partial)
        }
    }

    // MARK: - SpeechAnalyzer (macOS 26)

    struct Chunk: Sendable {
        let text: String
        let range: CMTimeRange
        let isFinal: Bool
    }

    private static func install(_ module: any SpeechModule, progress: Progress?) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
        let p = request.progress
        let watcher = Task {
            while !Task.isCancelled {
                await progress?(p.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { watcher.cancel() }
        try await request.downloadAndInstall()
    }

    private static func analyze<Results: AsyncSequence & Sendable>(
        url: URL,
        duration: TimeInterval,
        module: any SpeechModule,
        progress: @escaping Progress,
        partial: @escaping Partial,
        results: () -> Results
    ) async throws -> [Segment] where Results.Element == Chunk {
        try await install(module, progress: nil)

        let file = try AVAudioFile(forReading: url)
        let total = max(duration, Double(file.length) / file.fileFormat.sampleRate, 0.1)
        let analyzer = SpeechAnalyzer(modules: [module])
        let stream = results()

        let collector = Task {
            var finals: [Segment] = []
            for try await chunk in stream {
                let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let segment = Segment(start: chunk.range.start.seconds, end: chunk.range.end.seconds, text: text)
                if chunk.isFinal {
                    if !text.isEmpty { finals.append(segment) }
                    await partial(finals)
                } else {
                    await partial(text.isEmpty ? finals : finals + [segment])
                }
                let end = chunk.range.end.seconds
                if end.isFinite { await progress(min(end / total, 0.99)) }
            }
            return finals
        }

        do {
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            collector.cancel()
            throw error
        }
        return try await collector.value
    }

    // MARK: - SFSpeechRecognizer (clásico)

    private static func legacy(
        url: URL,
        duration: TimeInterval,
        locale: Locale,
        progress: @escaping Progress,
        partial: @escaping Partial
    ) async throws -> [Segment] {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { throw TranscriptionError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        // SFSpeech no lee Ogg/Opus: se pasa a WAV PCM temporal.
        let wav = try pcmCopy(of: url)
        defer { try? FileManager.default.removeItem(at: wav) }

        let request = SFSpeechURLRecognitionRequest(url: wav)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let total = max(duration, 0.1)
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                let once = OnceFlag()
                let chunks = ChunkAccumulator()
                box.task = recognizer.recognitionTask(with: request) { result, error in
                    if let result {
                        // On-device, la transcripción se reinicia tras cada pausa; el resultado
                        // que cierra cada tramo trae metadata y tiempos reales.
                        let segs = result.bestTranscription.segments
                        let segments = chunks.update(
                            result.bestTranscription.formattedString,
                            start: segs.first?.timestamp ?? 0,
                            end: segs.last.map { $0.timestamp + $0.duration } ?? 0,
                            endOfUtterance: result.speechRecognitionMetadata != nil
                        )
                        let reached = chunks.lastEnd
                        Task {
                            await partial(segments)
                            await progress(min(reached / total, 0.99))
                        }
                        if result.isFinal, once.take() { cont.resume(returning: chunks.committedSegments) }
                    }
                    if let error, once.take() {
                        let done = chunks.committedSegments
                        if done.isEmpty { cont.resume(throwing: error) } else { cont.resume(returning: done) }
                    }
                }
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    private static func pcmCopy(of url: URL) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        let output = try AVAudioFile(forWriting: out, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1 << 16) else { return url }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
        return out
    }
}

private final class TaskBox: @unchecked Sendable {
    var task: SFSpeechRecognitionTask?
}

/// Une los tramos que SFSpeech entrega por separado en audios largos.
/// Cada tramo termina con un resultado que trae `speechRecognitionMetadata`.
private final class ChunkAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var committed: [Segment] = []
    private var partial: Segment?

    var committedSegments: [Segment] {
        lock.lock(); defer { lock.unlock() }
        return committed
    }

    var lastEnd: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return committed.last?.end ?? 0
    }

    func update(_ text: String, start: TimeInterval, end: TimeInterval, endOfUtterance: Bool) -> [Segment] {
        lock.lock(); defer { lock.unlock() }
        if endOfUtterance {
            if !text.isEmpty { committed.append(Segment(start: start, end: end, text: text)) }
            partial = nil
        } else {
            // Los parciales llegan sin tiempos: se colocan tras el último tramo cerrado.
            let at = committed.last?.end ?? 0
            partial = Segment(start: at, end: at, text: text)
        }
        return committed + (partial.map { [$0] } ?? [])
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
