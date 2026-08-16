// Nuru Live "Broadcast Studio" — the floating "you're still live" island.
// RootView shows this on every screen while BroadcastCenter.shared has an
// active controller and the full-screen surface is minimized — the
// broadcaster's own analogue to RadioMiniPlayer, just simpler: broadcasting
// is rare enough (one member at a time, staff/cell-leader gated) that it
// doesn't need to wrap the hardware Dynamic Island cutout the way the
// always-available radio pill does. A plain floating capsule below the
// status area reads clearly without that complexity.
import SwiftUI

struct BroadcastMiniPlayer: View {
    @ObservedObject var controller: BroadcastController
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmEnd = false
    @State private var dim = false

    private var isReconnecting: Bool {
        if case .reconnecting = controller.phase { return true }
        return false
    }
    private var isFailed: Bool {
        if case .failed = controller.phase { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                onOpen()
            } label: {
                HStack(spacing: 8) {
                    dot
                    VStack(alignment: .leading, spacing: 1) {
                        Text(statusLabel)
                            .font(.inter(10, .bold)).kerning(1.1).foregroundStyle(statusColor)
                        if let startedAt = controller.startedAt {
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                Text(formatDuration(ctx.date.timeIntervalSince(startedAt)))
                                    .font(.inter(12, .semibold)).monospacedDigit().foregroundStyle(.white)
                            }
                        } else {
                            Text(controller.session.title)
                                .font(.inter(12, .semibold)).foregroundStyle(.white).lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to your broadcast")

            Spacer(minLength: 6)

            Button {
                Haptics.action()
                confirmEnd = true
            } label: {
                Icon(.x, size: 12, color: .white.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("End stream")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.black, in: Capsule())
        .overlay(Capsule().stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .padding(.horizontal, Nuru.S.base)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .confirmationDialog("End this stream?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End stream", role: .destructive) {
                Task { await controller.end() }
            }
            Button("Keep going", role: .cancel) {}
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Nuru broadcast in progress — tap to return")
    }

    private var statusLabel: String {
        if isFailed { return "RECONNECT NEEDED" }
        if isReconnecting { return "RECONNECTING" }
        switch controller.videoSource {
        case .document: return "LIVE · DOCUMENT"
        case .screen: return "LIVE · SCREEN"
        case .camera: return "LIVE"
        }
    }
    private var statusColor: Color { isFailed || isReconnecting ? Nuru.gold : .white }

    private var dot: some View {
        Circle()
            .fill(isFailed ? Nuru.gold : Color(hex: 0xEF4444))
            .frame(width: 7, height: 7)
            .opacity(dim ? 0.3 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dim = true }
            }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
