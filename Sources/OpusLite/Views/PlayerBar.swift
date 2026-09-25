import SwiftUI

struct PlayerBar: View {
    @Bindable var player: Player

    var body: some View {
        VStack(spacing: 10) {
            WaveformView(samples: player.waveform, progress: progress) { fraction in
                player.seek(to: fraction * player.duration)
            }
            .frame(height: 44)

            HStack(spacing: 18) {
                Button(action: player.toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: .option)
                .help(player.isPlaying ? "Pausa (⌥ Espacio)" : "Reproducir (⌥ Espacio)")

                Button { player.skip(-15) } label: {
                    Image(systemName: "gobackward.15").font(.system(size: 18))
                }
                .buttonStyle(.borderless)
                .help("Atrás 15 s")

                Text("\(player.currentTime.clock) / \(player.duration.clock)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 86)

                Button { player.skip(15) } label: {
                    Image(systemName: "goforward.15").font(.system(size: 18))
                }
                .buttonStyle(.borderless)
                .help("Adelante 15 s")

                Spacer()

                Menu {
                    Picker("Velocidad", selection: $player.rate) {
                        ForEach([0.75, 1, 1.25, 1.5, 2] as [Float], id: \.self) { r in
                            Text(r.formatted() + "×").tag(r)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(player.rate.formatted() + "×").font(.callout.monospacedDigit())
                }
                .menuStyle(.button)
                .fixedSize()
                .help("Velocidad")

                HStack(spacing: 6) {
                    Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Slider(value: $player.volume, in: 0...1)
                        .controlSize(.small)
                        .frame(width: 90)
                }
            }
            .disabled(player.duration == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var progress: Double {
        player.duration > 0 ? player.currentTime / player.duration : 0
    }
}

/// Barras de la forma de onda; la parte reproducida en color. Clic o arrastre para buscar.
struct WaveformView: View {
    let samples: [Float]
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let count = samples.isEmpty ? 120 : samples.count
                let step = size.width / CGFloat(count)
                let barWidth = max(step * 0.55, 1)
                for i in 0..<count {
                    let value = samples.isEmpty ? 0.08 : CGFloat(samples[i])
                    let h = max(value * size.height, 2)
                    let x = CGFloat(i) * step + (step - barWidth) / 2
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                    let played = Double(i) / Double(count) < progress
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                             with: .color(played ? Color.accentColor : Color.secondary.opacity(0.35)))
                }
                let x = size.width * progress
                ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.accentColor))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: -2, width: 8, height: 8)), with: .color(.accentColor))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    onSeek(min(max(value.location.x / geo.size.width, 0), 1))
                }
            )
        }
    }
}
