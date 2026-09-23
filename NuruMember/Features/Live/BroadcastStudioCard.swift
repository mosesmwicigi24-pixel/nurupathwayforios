// The broadcaster's "Broadcast" card — Go Live / return-to-broadcast / My
// Broadcasts — lifted out of the old Live tab so it can sit at the top of
// Events (PARTNERS_PROGRAMME §0: "Live (broadcasters only, live:go) moves into
// Events as a Broadcast card"). Callers gate it with
// LiveBroadcastEligibility.canGoLive — this card never checks itself, so a
// non-broadcaster is never shown a scope they'd then be refused for.
//
// The navy studio card, the breathing Go Live pill and the "LIVE now — watch"
// swap are exactly the L4 taste-pass pieces (see NuruLiveTabView's header
// note); the My Broadcasts page itself is NuruLiveTabView, pushed.
import SwiftUI

struct BroadcastStudioCard: View {
    /// When set, a "My Broadcasts" row appears under the pill and calls this
    /// (Events pushes the stewardship page). Nil on that page itself.
    var onMyBroadcasts: (() -> Void)? = nil

    @ObservedObject private var broadcast = BroadcastCenter.shared
    @ObservedObject private var liveDiscovery = LiveDiscoveryCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showGoLiveSheet = false
    @State private var breathe = false

    /// The church-wide stream someone ELSE is broadcasting right now, if
    /// any — `LiveDiscoveryCenter.streams` already excludes this device's
    /// own active broadcast (see its `ingest` header comment), so this can
    /// never be "my own" stream.
    private var churchStreamLive: LiveStreamSummary? {
        liveDiscovery.streams.first { $0.isChurch }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BROADCAST").font(.inter(10, .bold)).kerning(2.4).foregroundStyle(Nuru.gold.opacity(0.85))
                Text("Nuru Live").font(.fraunces(24, .semibold)).foregroundStyle(.white)
                Text("Bring the family together, wherever they are.")
                    .font(.inter(12)).foregroundStyle(.white.opacity(0.65))
            }
            if broadcast.controller == nil, let live = churchStreamLive {
                watchNowRow(live)
            } else {
                goLivePill
            }
            if let onMyBroadcasts {
                Button {
                    Haptics.tap(); onMyBroadcasts()
                } label: {
                    HStack(spacing: 10) {
                        Icon(.playCircle, size: 16, color: Nuru.gold)
                        Text("My Broadcasts").font(.inter(13, .semibold)).foregroundStyle(.white)
                        Spacer(minLength: 0)
                        Icon(.chevronRight, size: 14, color: .white.opacity(0.6))
                    }
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.pressableSubtle)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Nuru.navy, Nuru.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
        .sheet(isPresented: $showGoLiveSheet) {
            GoLiveSetupSheet { BroadcastCenter.shared.start(session: $0) }
        }
    }

    private var goLivePill: some View {
        let live = broadcast.controller != nil
        return Button {
            Haptics.tap()
            if live { broadcast.restore() } else { showGoLiveSheet = true }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Nuru.gold.opacity(0.45), lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .scaleEffect(breathe ? 1.4 : 1)
                        .opacity(breathe ? 0 : 0.85)
                    Circle().fill(live ? Color.white.opacity(0.16) : Nuru.gold).frame(width: 40, height: 40)
                    Image(systemName: "video.fill").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(live ? .white : Nuru.navy)
                }
                Text(live ? "You're live — tap to return" : "Go Live")
                    .font(.inter(15, .bold)).foregroundStyle(live ? .white : Nuru.navy)
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 15, color: live ? .white.opacity(0.7) : Nuru.navy.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
            .background(live ? Color.white.opacity(0.10) : Nuru.gold, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(live ? 0.16 : 0), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { breathe = true }
        }
    }

    private func watchNowRow(_ stream: LiveStreamSummary) -> some View {
        Button {
            Haptics.tap()
            liveDiscovery.markSeen(stream.streamId)
            liveDiscovery.requestedItem = .live(stream)
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: 0xDC2626)).frame(width: 6, height: 6)
                    Text("LIVE").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(.white)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(hex: 0xDC2626), in: Capsule())
                Text(stream.title).font(.inter(13, .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 8)
                Text("Watch").font(.inter(12, .bold)).foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Nuru.gold, in: Capsule())
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.gold.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.pressableSubtle)
    }
}
