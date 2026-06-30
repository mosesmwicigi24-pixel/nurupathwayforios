// Your Calling — the native port of screens/GiftsScreen.tsx (read view). Shows the
// member's spiritual-gifts assessment: top gifts, persona cards, and suggested
// serving tracks. When no assessment exists yet, invites them to take it (the
// question/scoring flow lands in a later pass).
import SwiftUI

@MainActor
final class GiftsViewModel: ObservableObject {
    @Published var gifts: MyGifts?
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { gifts = try await MemberAPI.myGifts() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your gifts." }
        loading = false
    }
}

struct GiftsView: View {
    @StateObject private var vm = GiftsViewModel()

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            LoadStateView(loading: vm.loading && vm.gifts == nil,
                          isEmpty: vm.gifts == nil, error: vm.error,
                          emptyText: "No gifts profile yet.", retry: { Task { await vm.load() } }) {
                if let g = vm.gifts { content(g) }
            }
        }
        .navigationTitle("Your Calling")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.gifts == nil { await vm.load() } }
    }

    @ViewBuilder
    private func content(_ g: MyGifts) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                if let a = g.assessment {
                    summaryCard(a, personas: g.personas)
                    if !g.personas.isEmpty {
                        Text("YOUR GIFTS").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.gold)
                        ForEach(g.personas) { personaCard($0) }
                    }
                    if !g.suggestedTracks.isEmpty {
                        Text("WAYS TO SERVE").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.gold).padding(.top, Nuru.S.sm)
                        ForEach(g.suggestedTracks) { trackRow($0) }
                    }
                } else {
                    discoverCTA
                }
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
    }

    private func summaryCard(_ a: GiftAssessment, personas: [GiftPersona]) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            Icon(.sparkles, size: 28, color: Nuru.gold)
            Text("Your top gifts").font(.nTitle).foregroundStyle(Nuru.ink)
            if let summary = a.personaSummary, !summary.isEmpty {
                Text(summary).font(.nBody).foregroundStyle(Nuru.muted).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Nuru.S.sm) {
                ForEach(a.topGifts.prefix(3), id: \.self) { key in
                    let label = personas.first { $0.giftKey == key }?.title ?? key.capitalized
                    Text(label).font(.inter(12, .semibold)).foregroundStyle(Nuru.goldChipText)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Nuru.goldChipBg, in: Capsule())
                }
            }
        }
        .padding(Nuru.S.base).giftCard()
    }

    private func personaCard(_ p: GiftPersona) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack(spacing: Nuru.S.sm) {
                Text(p.emoji ?? "✨").font(.system(size: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.title).font(.nHeading).foregroundStyle(Nuru.ink)
                    Text(p.personaName).font(.nCaption).foregroundStyle(Nuru.gold)
                }
            }
            if let tagline = p.tagline, !tagline.isEmpty {
                Text(tagline).font(.nCaption).foregroundStyle(Nuru.muted).italic()
            }
            Text(p.summary).font(.nBody).foregroundStyle(Nuru.ink).fixedSize(horizontal: false, vertical: true)
            if !p.strengths.isEmpty {
                FlowChips(p.strengths)
            }
        }
        .padding(Nuru.S.base).giftCard()
    }

    private func trackRow(_ t: ServingTrack) -> some View {
        HStack(spacing: Nuru.S.md) {
            ZStack { Circle().fill(Nuru.goldTint).frame(width: 38, height: 38); Icon(.handHeart, size: 18, color: Nuru.gold) }
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                Text(t.description).font(.nMicro).foregroundStyle(Nuru.faint).lineLimit(2)
            }
            Spacer(minLength: 0)
            if t.matchCount > 0 {
                Text("\(t.matchCount) match").font(.nMicro).foregroundStyle(Nuru.successText)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Nuru.successBg, in: Capsule())
            }
        }
        .padding(Nuru.S.base).giftCard()
    }

    private var discoverCTA: some View {
        VStack(spacing: Nuru.S.md) {
            Icon(.sparkles, size: 40, color: Nuru.gold)
            Text("Discover your gifts").font(.nTitle).foregroundStyle(Nuru.ink)
            Text("Take the short assessment to reveal how God has wired you to serve.")
                .font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            Text("Assessment coming soon").font(.nMicro).foregroundStyle(Nuru.faint)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.xl).padding(.horizontal, Nuru.S.base)
        .giftCard()
    }
}

/// Strengths chips in a horizontal scroll (keeps layout simple + robust).
private struct FlowChips: View {
    let items: [String]
    init(_ items: [String]) { self.items = items }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { s in
                    Text(s).font(.nMicro).foregroundStyle(Nuru.ink600)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Nuru.surface, in: Capsule())
                }
            }
        }
    }
}

private extension View {
    func giftCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
    }
}
