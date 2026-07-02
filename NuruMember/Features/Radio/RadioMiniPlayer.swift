// Floating now-playing capsule — shown on Home (just above the tab bar) while
// Nuru Radio is tuned and the full player page is closed. Driven entirely by
// RadioCenter.shared, so it reflects the same stream the Dynamic Island shows:
// artwork/glyph · LIVE dot + title · play/pause · ✕ (stop). Tapping the body
// reopens the full player. Small standalone struct per the Home-cards rule.
import SwiftUI

struct RadioMiniPlayer: View {
    @ObservedObject private var center = RadioCenter.shared
    let open: () -> Void

    init(open: @escaping () -> Void) { self.open = open }

    var body: some View {
        // The `if let` lives inside a container so the slide-up/away transition
        // actually runs when the radio is tuned/stopped (attached to conditional
        // content directly, SwiftUI would pop it in with no animation).
        ZStack {
            if let p = center.program {
                capsule(p)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: center.program?.id)
    }

    private func capsule(_ p: RadioProgram) -> some View {
        Button {
            Haptics.tap()
            open()
        } label: {
            HStack(spacing: 10) {
                thumb(p)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        if p.live {
                            Circle().fill(Color(hex: 0xF87171)).frame(width: 5, height: 5)
                            Text("LIVE · NURU RADIO").font(.inter(8, .bold)).kerning(1.2)
                                .foregroundStyle(Color(hex: 0xF87171))
                        } else {
                            Text("NURU RADIO").font(.inter(8, .bold)).kerning(1.2)
                                .foregroundStyle(Nuru.gold.opacity(0.9))
                        }
                    }
                    Text(p.title).font(.inter(12, .semibold)).foregroundStyle(.white)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 6)
                Button {
                    Haptics.tap()
                    center.togglePlay()
                } label: {
                    Image(systemName: center.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Nuru.navy)
                        .contentTransition(.symbolEffect(.replace))
                        .offset(x: center.playing ? 0 : 1)
                        .frame(width: 34, height: 34)
                        .background(Nuru.gold, in: Circle())
                        .shadow(color: Nuru.gold.opacity(0.45), radius: 6, y: 3)
                }
                .buttonStyle(.pressable)
                .animation(.easeInOut(duration: 0.2), value: center.playing)
                .accessibilityLabel(center.playing ? "Pause radio" : "Play radio")
                Button {
                    Haptics.tap()
                    center.stop()
                } label: {
                    Icon(.x, size: 13, color: .white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Stop radio")
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                LinearGradient(colors: [Color(hex: 0x142743), Color(hex: 0x0A1628)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressableSubtle)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .accessibilityHint("Opens the radio player")
    }

    private func thumb(_ p: RadioProgram) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1B3050), Color(hex: 0x0E1E35)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let a = p.artworkUrl, let u = URL(string: a) {
                CachedAsyncImage(url: u) { ph in
                    if let img = ph.image { img.resizable().scaledToFill() }
                    else { glyph }
                }
            } else {
                glyph
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var glyph: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 15)).foregroundStyle(Nuru.gold.opacity(0.9))
    }
}
