import AVFoundation
import Observation

/// Graba notas de voz del micrófono a .m4a en la carpeta de la app.
@MainActor
@Observable
final class Recorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = Array(repeating: 0, count: 48)
    var error: String?

    private var recorder: AVAudioRecorder?
    private var ticker: Task<Void, Never>?

    static let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpusLite/Grabaciones", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func start() async {
        error = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Sin permiso de micrófono. Actívalo en Ajustes del Sistema › Privacidad › Micrófono."
            return
        }
        let name = "Grabación " + Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
        let url = Self.folder.appendingPathComponent(name).appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = r
            isRecording = true
            elapsed = 0
            levels = Array(repeating: 0, count: levels.count)
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let r = self.recorder else { return }
                    r.updateMeters()
                    let db = r.averagePower(forChannel: 0)
                    let level = max(0, min(1, (db + 50) / 50))
                    self.levels.removeFirst()
                    self.levels.append(level)
                    self.elapsed = r.currentTime
                    try? await Task.sleep(for: .milliseconds(60))
                }
            }
        } catch {
            self.error = "No se pudo grabar: \(error.localizedDescription)"
        }
    }

    /// Detiene y devuelve el archivo grabado.
    func stop() -> URL? {
        ticker?.cancel()
        guard let r = recorder else { return nil }
        r.stop()
        recorder = nil
        isRecording = false
        return r.url
    }

    func discard() {
        if let url = stop() { try? FileManager.default.removeItem(at: url) }
    }
}
