// Nuru Live L4 — the Live tab (docs/LIVE_STREAMING.md L4 section). RootView
// only mounts this for a member whose /me permissions include `live:go`
// (LiveBroadcastEligibility.canGoLive) — everyone else keeps the four-tab bar
// and watches through Home's LIVE banner / the cell card, unchanged. This is
// the broadcaster's own "backstage": the exact L3 Go Live entry point Home
// already uses (GoLiveSetupSheet → GoLiveBroadcastView, offering whichever of
// church/cell the signed-in profile is eligible for — no forced scope, same
// as Home's header icon), plus the L2 Replays list hosted directly on the
// page rather than behind a sheet.
import SwiftUI

struct NuruLiveTabView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var showGoLiveSheet = false
    @State private var goLiveSession: GoLiveSession?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: Nuru.S.base) {
                        goLiveCard
                        replaysSection
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Nuru.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showGoLiveSheet) {
            GoLiveSetupSheet { goLiveSession = $0 }
        }
        .fullScreenCover(item: $goLiveSession) { GoLiveBroadcastView(session: $0) }
    }

    // MARK: Header — the same cream hero-band idiom every folded tab uses.

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🔴 NURU LIVE").font(.inter(11, .bold)).kerning(2).foregroundStyle(Color(hex: 0x9A7A2A))
            Text("Go live").font(.fraunces(28, .semibold)).foregroundStyle(Nuru.navy)
            Text("Broadcast to the church or your cell, and revisit past streams.")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x59667C))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen).padding(.top, 60).padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    // MARK: Go Live entry — reuses the L3 flow exactly as Home does.

    private var goLiveCard: some View {
        Button {
            Haptics.tap()
            showGoLiveSheet = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Nuru.gold)
                    Image(systemName: "video.fill").font(.system(size: 18)).foregroundStyle(Nuru.navy)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Go live now").font(.nCardTitle).foregroundStyle(Nuru.ink)
                    Text("Church or your cell — video or audio").font(.nCardMeta).foregroundStyle(Nuru.muted)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 16, color: Nuru.gold)
                    .frame(width: 32, height: 32)
                    .background(Nuru.gold.opacity(0.12), in: Circle())
            }
            .padding(Nuru.S.base)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: Replays — L2's list, hosted directly (not a sheet) per L4.

    private var replaysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REPLAYS").font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0xB08A1E))
                .padding(.horizontal, 4)
            // Unscoped — everything visible to this broadcaster (church + their
            // own cell), matching what LiveReplaysView already documents as its
            // "both nil" default.
            LiveReplaysView(embedded: true)
        }
    }
}
