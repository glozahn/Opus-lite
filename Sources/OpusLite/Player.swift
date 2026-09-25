import AVFoundation
import Observation

/// Player for the selected item, with an observable position for the UI.
@MainActor
@Observable
final class Player {
    private(set) var loadedID: UUID?
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    var currentTime: TimeInterval = 0
    var waveform: [Float] = []

    var rate: Float = 1 {
        didSet { player?.rate = rate }
    }

    var volume: Float = 1 {
        didSet { player?.volume = volume }
    }

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    private var loading: Task<Void, Never>?

    func load(_ item: LibraryItem?) {
        guard item?.id != loadedID else { return }
        stop()
        loading?.cancel()
        player = nil
        waveform = []
        currentTime = 0
        loadedID = item?.id
        guard let item, !item.kind.isDocument, item.fileExists else {
            duration = 0
            return
        }
        duration = item.duration
        loading = Task {
            guard let url = try? await Media.playableAudio(for: item), !Task.isCancelled else { return }
            if let p = try? AVAudioPlayer(contentsOf: url) {
                p.enableRate = true
                p.rate = rate
                p.volume = volume
                p.prepareToPlay()
                player = p
                duration = p.duration
            }
            let wave = await Media.waveform(of: url)
            if !Task.isCancelled, loadedID == item.id { waveform = wave }
        }
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
        player.play()
        isPlaying = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
                if !p.isPlaying {
                    self.isPlaying = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
    }

    func stop() {
        player?.stop()
        isPlaying = false
        ticker?.cancel()
    }

    func seek(to time: TimeInterval) {
        let t = min(max(time, 0), duration)
        player?.currentTime = t
        currentTime = t
    }

    func skip(_ delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    /// Jumps to a point in the text and plays.
    func play(from time: TimeInterval) {
        seek(to: time)
        play()
    }
}
