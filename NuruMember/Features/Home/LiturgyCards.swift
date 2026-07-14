// The liturgy Home + celebrations rail (intelligence Phase 4).
//   • HomeLiturgyCard — Home breathes with the hours: the current part's prayer
//     line (morning/midday/evening/night), coloured by the church season.
//     Self-loading; collapses to nothing until the line arrives.
//   • CelebrationsRail — the congregation's recent milestones (server-detected,
//     Phase 4 moments) with one-tap blessings (🙌 ❤️ 🔥), optimistic updates.
import SwiftUI

struct HomeLiturgyCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var lit: HomeLiturgy?

    private func partLabel(_ p: String) -> String {
        switch p {
        case "morning": return "MORNING"
        case "midday": return "MIDDAY"
        case "evening": return "EVENING"
        default: return "NIGHT"
        }
    }

    private func partEmoji(_ p: String) -> String {
        switch p {
        case "morning": return "🌅"
        case "midday": return "☀️"
        case "evening": return "🌆"
        default: return "🌙"
        }
    }

    var body: some View {
        Group {
            if lit == nil {
                // Zero-height anchor: keeps this view INSTALLED while empty so
                // .task actually runs (a bare empty Group never appears, so its
                // task never fires — the card would stay dead forever).
                Color.clear.frame(height: 0)
            }
            if let lit {
                if let art = lit.art, let url = URL(string: art.url), !art.url.isEmpty {
                    // The hour, beheld: a taller photograph of the hour it names,
                    // hidden a little under the deep-navy block, with the hour +
                    // brand at the top and the prayer line resting at the BOTTOM
                    // where the veil is deepest — so the type reads clearly (owner
                    // ask). Everything is owned+clipped, never inflates layout.
                    Color.clear
                        .frame(height: 206)
                        .overlay {
                            CachedAsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                } else {
                                    LinearGradient(colors: [Color(hex: 0x16273F), Color(hex: 0x0A1C33)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                }
                            }
                        }
                        .clipped()
                        .overlay { DeepNavyBlock() }
                        .overlay(alignment: .topLeading) { litKicker(lit).padding(18) }
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(lit.line)
                                    .font(.fraunces(19)).foregroundStyle(.white)
                                    .lineSpacing(4)
                                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let ref = lit.scriptureRef {
                                    Text(ref)
                                        .font(.inter(11, .semibold)).foregroundStyle(.white.opacity(0.92))
                                        .lineLimit(1)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Color.black.opacity(0.28), in: Capsule())
                                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                }
                            }
                            .padding(18)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    // Offline / older backend: the classic navy card, content-sized.
                    VStack(alignment: .leading, spacing: 10) {
                        litKicker(lit)
                        Text(lit.line)
                            .font(.fraunces(18)).foregroundStyle(.white)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                        if let ref = lit.scriptureRef {
                            HStack {
                                Spacer(minLength: 0)
                                Text(ref)
                                    .font(.inter(11, .semibold)).foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [Color(hex: 0x0F2A47), Color(hex: 0x0A1C33)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(alignment: .topTrailing) {
                                Circle().fill(Color(hex: 0xE8CA6C).opacity(0.14))
                                    .frame(width: 150, height: 150).blur(radius: 38)
                                    .offset(x: 45, y: -55)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    )
                }
            }
        }
        .task { lit = try? await MemberAPI.homeLiturgy() }
        .onChange(of: scenePhase) { _, phase in
            // The tab shell keeps Home alive for the whole session — without
            // this an overnight-resident app shows yesterday's card forever.
            if phase == .active { Task { lit = try? await MemberAPI.homeLiturgy() } }
        }
    }

    /// The hour + brand row — shared by the tableau (top overlay) and the
    /// classic offline card. Gold hour label, then the Nuru Pathway lockup.
    @ViewBuilder
    private func litKicker(_ lit: HomeLiturgy) -> some View {
        HStack(spacing: 7) {
            Text(partEmoji(lit.part)).font(.system(size: 15))
            Text(lit.isSunday ? "SUNDAY · \(partLabel(lit.part))" : "\(partLabel(lit.part)) · \(lit.season.uppercased())")
                .font(.inter(10.5, .bold)).kerning(1.6)
                .foregroundStyle(Color(hex: 0xF2DDA0))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .lineLimit(1)
            BrandMark(size: 14)
            Text("Nuru Pathway")
                .font(.inter(10.5, .semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .lineLimit(1)
            Icon(.badgeCheck, size: 11, color: Color(hex: 0xF2DDA0))
            Spacer(minLength: 0)
        }
    }
}

struct CelebrationsRail: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var moments: [CommunityMoment] = []

    var body: some View {
        Group {
            if moments.isEmpty {
                Color.clear.frame(height: 0) // install-anchor — see HomeLiturgyCard
            }
            if !moments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("🎉").font(.system(size: 13))
                        Text("CELEBRATE THE FAMILY")
                            .font(.inter(10.5, .bold)).kerning(1.6)
                            .foregroundStyle(Nuru.muted)
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(moments) { m in
                                MomentCard(moment: m) { kind in
                                    bless(m, kind: kind)
                                }
                            }
                        }
                        .padding(.horizontal, Nuru.S.screen)
                    }
                }
            }
        }
        .task { moments = (try? await MemberAPI.communityMoments()) ?? [] }
        .onChange(of: scenePhase) { _, phase in
            // The tab shell keeps Home alive for the whole session — without
            // this an overnight-resident app shows yesterday's card forever.
            if phase == .active { Task { moments = (try? await MemberAPI.communityMoments()) ?? [] } }
        }
    }

    private func bless(_ m: CommunityMoment, kind: String) {
        guard let idx = moments.firstIndex(where: { $0.momentId == m.momentId }) else { return }
        Haptics.action()
        var updated = moments[idx]
        // Optimistic: move my blessing to the tapped kind.
        if let prev = updated.myBlessing {
            if prev == "amen" { updated.amenCount -= 1 }
            if prev == "heart" { updated.heartCount -= 1 }
            if prev == "fire" { updated.fireCount -= 1 }
        }
        if kind == "amen" { updated.amenCount += 1 }
        if kind == "heart" { updated.heartCount += 1 }
        if kind == "fire" { updated.fireCount += 1 }
        updated.myBlessing = kind
        moments[idx] = updated
        Task { _ = try? await MemberAPI.bless(m.momentId, kind: kind) }
    }
}

private struct MomentCard: View {
    let moment: CommunityMoment
    let onBless: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Avatar(url: moment.avatarUrl, name: moment.fullName, size: 30)
                Text(moment.fullName.split(separator: " ").first.map(String.init) ?? moment.fullName)
                    .font(.inter(13, .bold)).foregroundStyle(Nuru.ink)
                    .lineLimit(1)
            }
            Text(moment.title)
                .font(.fraunces(15)).foregroundStyle(Nuru.navyMid)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
            HStack(spacing: 6) {
                blessChip("🙌", "amen", moment.amenCount)
                blessChip("❤️", "heart", moment.heartCount)
                blessChip("🔥", "fire", moment.fireCount)
            }
        }
        .padding(14)
        .frame(width: 210, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func blessChip(_ emoji: String, _ kind: String, _ count: Int) -> some View {
        let mine = moment.myBlessing == kind
        return Button { onBless(kind) } label: {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 12))
                if count > 0 {
                    Text("\(count)").font(.inter(11, .bold))
                        .foregroundStyle(mine ? Nuru.navy : Nuru.muted)
                        .contentTransition(.numericText())   // ticks up, never snaps
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(mine ? Color(hex: 0xE8CA6C).opacity(0.35) : Nuru.tintBlue, in: Capsule())
            .overlay(Capsule().stroke(mine ? Color(hex: 0xC9A227).opacity(0.6) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}
