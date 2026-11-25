// Read aloud — the controls every reader shares (member suggestion,
// 2026-11-21). A reader builds its ListenReading once (a @State, so a scroll
// never re-cuts the words), puts a ListenHost round its own header button and
// another round ListenBar just above its bottom action:
//
//   header   [Listen]            → tap: read from the top
//   bar      ⏮ ⏸ ⏭  Reading aloud · 3 of 12  [1×] ✕
//
// ListenHost is the only thing that watches the engine, so a paragraph turning
// redraws the button and the bar, never the whole reader. The bar shows only
// while this reading is loaded (playing or paused); its colours come from the
// reader's own palette, so it sits on the day page and the night page alike.
// Android's twin: feature/listen/ListenControls.kt.
import SwiftUI

/// Watches the engine for one reading and hands its controls to `content`.
struct ListenHost<Content: View>: View {
    let reading: ListenReading
    private let content: (ListenControls) -> Content
    @ObservedObject private var engine = ReadAloud.shared

    init(_ reading: ListenReading, @ViewBuilder content: @escaping (ListenControls) -> Content) {
        self.reading = reading
        self.content = content
    }

    var body: some View {
        content(engine.controls(for: reading))
    }
}

/// The colours of the bar on a reader's page.
struct ListenColors {
    var bar: Color
    var ink: Color
    var inkDim: Color
    var accent: Color
    var onAccent: Color
    var border: Color
}

extension ReaderPalette {
    /// The bar on a plan reader's page, day or night.
    var listenColors: ListenColors {
        ListenColors(bar: card, ink: ink, inkDim: inkDim, accent: gold, onAccent: Color(hex: 0x0A1628), border: border)
    }
}

/// The player, shown while this reading is loaded. Put it directly above the
/// reader's bottom action (or at the page's foot).
struct ListenBar: View {
    let controls: ListenControls
    let colors: ListenColors

    var body: some View {
        VStack(spacing: 0) {
            if controls.active {
                bar.transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controls.active)
    }

    private var bar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                barButton(.skipBack, label: "Previous paragraph", enabled: controls.index > 0) {
                    ReadAloud.shared.skip(-1)
                }
                playPause
                barButton(.skipForward, label: "Next paragraph", enabled: true) {
                    ReadAloud.shared.skip(1)
                }
                words.padding(.leading, 6)
                Spacer(minLength: 4)
                speedChip
                barButton(.x, label: "Stop reading aloud", enabled: true) {
                    ReadAloud.shared.stop()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            progressLine
        }
        .background(colors.bar)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(colors.border, lineWidth: 1))
        .padding(.bottom, 10)
    }

    private var playPause: some View {
        Button {
            Haptics.tap()
            ReadAloud.shared.toggle(controls.reading)
        } label: {
            Icon(controls.playing ? .pause : .play, size: 22, color: colors.onAccent)
                .frame(width: 44, height: 44)
                .background(colors.accent, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(controls.playing ? "Pause" : "Play")
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(controls.stateLine)
                .font(.inter(13, .semibold)).foregroundStyle(colors.ink)
                .lineLimit(1)
            Text(controls.placeLine)
                .font(.inter(11)).foregroundStyle(colors.inkDim)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var speedChip: some View {
        Button {
            Haptics.selection()
            ReadAloud.shared.cycleSpeed()
        } label: {
            Text(ListenSpeed.label(controls.speed))
                .font(.inter(12, .bold)).foregroundStyle(colors.ink)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .overlay(Capsule().stroke(colors.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Speed \(ListenSpeed.label(controls.speed)). Tap to change")
    }

    private func barButton(_ icon: Lucide, label: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Icon(icon, size: 18, color: enabled ? colors.inkDim : colors.inkDim.opacity(0.35))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// How far through the reading, by paragraph.
    private var progressLine: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(colors.border)
                Rectangle().fill(colors.accent)
                    .frame(width: g.size.width * CGFloat(controls.progress))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
