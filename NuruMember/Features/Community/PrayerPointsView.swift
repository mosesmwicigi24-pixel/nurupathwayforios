// AI Prayer Points (Prayer Room tab 4, docs: prayer-room-arc). Two surfaces
// over the intelligence layer's PrayerAiService, both consent-gated exactly
// like Profile's "Nuru Intelligence" switch (§1.1 — AI never gates/scores/
// touches money, it only ever writes words the member reviews):
//   • Assist — a Gemini-in-Gmail-style composer: seed a few points, get a
//     short draft prayer in the member's own voice (POST /me/prayer/assist).
//   • Gather — the corpus generator: distills prayer points from the member's
//     OWN Selah thoughts + private prayers + published prayer-wall posts
//     (POST /me/prayer/points). The member always edits/keeps/prays these
//     themselves — nothing here posts or sends anything.
import SwiftUI

struct PrayerPointsView: View {
    @State private var optedOut: Bool?
    @State private var consentBusy = false
    @State private var consentFailed = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Nuru.S.base) {
                Text("Let Nuru help you pray")
                    .font(.fraunces(21, .medium)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gentleEntrance()

                switch optedOut {
                case nil:
                    ProgressView().padding(.top, Nuru.S.xl)
                case true?:
                    ConsentGateCard(busy: consentBusy, failed: consentFailed) { Task { await enableAi() } }
                        .gentleEntrance(delay: 0.05)
                case false?:
                    AssistComposerCard()
                        .gentleEntrance(delay: 0.05)
                    GatherPointsCard()
                        .gentleEntrance(delay: 0.1)
                }
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, Nuru.S.lg)
            .padding(.bottom, Nuru.tabBarSpace)
        }
        .background(Nuru.paper.ignoresSafeArea())
        .task {
            if optedOut == nil { optedOut = (try? await MemberAPI.aiConsent()) ?? false }
        }
    }

    private func enableAi() async {
        guard !consentBusy else { return }
        consentBusy = true
        consentFailed = false
        do {
            _ = try await MemberAPI.setAiConsent(optOut: false)
            Haptics.success()
            withAnimation { optedOut = false }
        } catch {
            Haptics.error()
            consentFailed = true
        }
        consentBusy = false
    }
}

// MARK: - Consent gate (same covenant as Profile → Nuru Intelligence / the Sunday Letter)

private struct ConsentGateCard: View {
    let busy: Bool
    let failed: Bool
    let enable: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack(spacing: 8) {
                    Circle().fill(
                        LinearGradient(colors: [Color(hex: 0xC4B5FD), Color(hex: 0x7C3AED), Color(hex: 0x2A1259)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 26)
                        .overlay(Icon(.sparkles, size: 13, color: .white))
                    Text("NURU INTELLIGENCE").font(.inter(10, .bold)).tracking(1.6).foregroundStyle(Color(hex: 0x9A7A2A))
                }
                Text("Turn on AI personalization to use the prayer assistant.")
                    .font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                Text("Nuru remembers your journey to walk with you personally. Your prayer journal is never read — ever. This is the same switch as your Sunday Letter and personal companion; turning it on here turns it on everywhere, and you can turn it off again anytime in Profile.")
                    .font(.inter(12)).foregroundStyle(Nuru.muted).lineSpacing(3)
                if failed {
                    Text("Couldn't save that — check your connection and try again.")
                        .font(.inter(11, .medium)).foregroundStyle(Color(hex: 0xB91C1C))
                }
                Button {
                    Haptics.tap(); enable()
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(.white) }
                        Text("Turn on AI personalization").font(.inter(13, .bold)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: 0xC9A227), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(busy)
            }
        }
    }
}

// MARK: - (a) Assist composer — seed points → draft in the member's own voice

private struct AssistComposerCard: View {
    @State private var seed = ""
    @State private var draft = ""
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack(spacing: 8) {
                    Icon(.handHeart, size: 16, color: Nuru.gold)
                    Text("Draft a prayer").font(.nCardTitle).foregroundStyle(Nuru.navy)
                }
                Text("Jot a few seed points — Nuru drafts a short prayer in your own voice. You always edit it before you pray or keep it.")
                    .font(.nCardBody).foregroundStyle(Nuru.muted)
                TextField("e.g. wisdom for work, my sister's health, thankful for…", text: $seed, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.inter(13, .regular)).foregroundStyle(Nuru.navy)
                    .padding(Nuru.S.md)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        Task { await assist() }
                    } label: {
                        HStack(spacing: 6) {
                            if busy { ProgressView().tint(.white) } else { Icon(.sparkles, size: 13, color: .white) }
                            Text(busy ? "Drafting…" : "Draft with Nuru").font(.inter(12, .bold)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [Color(hex: 0xC4B5FD), Color(hex: 0x7C3AED), Color(hex: 0x2A1259)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(busy)
                }
                if failed {
                    Text("Nuru couldn't reach the assistant just now — try again in a moment.")
                        .font(.inter(11, .medium)).foregroundStyle(Color(hex: 0xB91C1C))
                }
                if !draft.isEmpty {
                    Divider().overlay(Nuru.border)
                    Text("YOUR DRAFT").font(.inter(10, .bold)).tracking(1.4).foregroundStyle(Color(hex: 0x9A7A2A))
                    TextField("", text: $draft, axis: .vertical)
                        .lineLimit(3...12)
                        .font(.inter(14, .regular)).foregroundStyle(Nuru.navy).lineSpacing(4)
                        .padding(Nuru.S.md)
                        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap(); UIPasteboard.general.string = draft
                        } label: {
                            Text("Copy").font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Color.white, in: Capsule())
                                .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                        Button {
                            Haptics.tap(); draft = ""; seed = ""
                        } label: {
                            Text("Discard").font(.inter(12, .semibold)).foregroundStyle(Nuru.muted)
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func assist() async {
        guard !busy else { return }
        busy = true
        failed = false
        Haptics.tap()
        do {
            draft = try await MemberAPI.prayerAssist(seed: seed)
        } catch {
            failed = true
            Haptics.error()
        }
        busy = false
    }
}

// MARK: - (b) Gather my prayer points — the corpus generator

private struct GatherPointsCard: View {
    @State private var points: [String] = []
    @State private var busy = false
    @State private var failed = false
    @State private var hasGathered = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack(spacing: 8) {
                    Icon(.list, size: 16, color: Nuru.gold)
                    Text("Gather my prayer points").font(.nCardTitle).foregroundStyle(Nuru.navy)
                }
                Text("Nuru reads across your own Selah thoughts, private prayers, and things you've shared to the wall — and distills what to pray through today.")
                    .font(.nCardBody).foregroundStyle(Nuru.muted)
                Button {
                    Task { await gather() }
                } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().tint(Nuru.navy) } else { Icon(.list, size: 13, color: Nuru.navy) }
                        Text(busy ? "Gathering…" : "Gather my prayer points")
                            .font(.inter(13, .bold)).foregroundStyle(Nuru.navy)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: 0xC9A227), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(busy)

                if failed {
                    Text("Couldn't gather your points just now — try again in a moment.")
                        .font(.inter(11, .medium)).foregroundStyle(Color(hex: 0xB91C1C))
                } else if hasGathered && points.isEmpty {
                    Text("Nothing to gather yet — write a Selah thought or a prayer first, and come back.")
                        .font(.inter(12)).foregroundStyle(Nuru.muted)
                } else if !points.isEmpty {
                    VStack(alignment: .leading, spacing: Nuru.S.sm) {
                        ForEach(Array(points.enumerated()), id: \.offset) { idx, p in
                            PrayerPointRow(index: idx, text: p) { updated in
                                points[idx] = updated
                            } onRemove: {
                                points.remove(at: idx)
                            }
                        }
                    }
                    .padding(.top, Nuru.S.sm)
                    HStack {
                        Button {
                            Haptics.tap()
                            UIPasteboard.general.string = points.enumerated()
                                .map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                        } label: {
                            Text("Copy all").font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Color.white, in: Capsule())
                                .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func gather() async {
        guard !busy else { return }
        busy = true
        failed = false
        Haptics.tap()
        do {
            points = try await MemberAPI.prayerPoints()
            hasGathered = true
        } catch {
            failed = true
            Haptics.error()
        }
        busy = false
    }
}

private struct PrayerPointRow: View {
    let index: Int
    let text: String
    let onEdit: (String) -> Void
    let onRemove: () -> Void
    @State private var editing: String

    init(index: Int, text: String, onEdit: @escaping (String) -> Void, onRemove: @escaping () -> Void) {
        self.index = index; self.text = text; self.onEdit = onEdit; self.onRemove = onRemove
        _editing = State(initialValue: text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.sm) {
            Text("\(index + 1)").font(.inter(12, .bold)).foregroundStyle(Nuru.gold)
                .frame(width: 18, alignment: .trailing)
            TextField("", text: $editing, axis: .vertical)
                .font(.inter(13, .regular)).foregroundStyle(Nuru.navy).lineSpacing(3)
                .onChange(of: editing) { _, newValue in onEdit(newValue) }
            Button { Haptics.tap(); onRemove() } label: {
                Icon(.x, size: 11, color: Color(hex: 0x9CA3AF))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}
