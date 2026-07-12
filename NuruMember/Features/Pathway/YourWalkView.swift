// Wave 3 — Your Walk: the member's whole journey as one gold thread.
// Every node is a real event with a real timestamp (no AI, no padding):
// began the pathway, modules finished, reflections written, levels passed,
// certificates sealed, verses mastered, plans completed, badges earned.
// Also home to FootprintsStrip — the faces of cell-mates who already
// walked a module, shown at the top of the lesson.
import SwiftUI

struct YourWalkView: View {
    @State private var events: [WalkEvent] = []
    @State private var loading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else if events.isEmpty {
                    VStack(spacing: 8) {
                        Icon(.flag, size: 26, color: Nuru.gold)
                        Text("Your walk begins with the next lesson you open.")
                            .font(.inter(14)).foregroundStyle(Nuru.ink)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 80).padding(.horizontal, 40)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
                            WalkNode(event: e, isFirst: i == 0, isLast: i == events.count - 1)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
                Spacer(minLength: Nuru.tabBarSpace)
            }
        }
        .background(Color(hex: 0xFAF7F0).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { events = (try? await MemberAPI.myWalk()) ?? []; loading = false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button { Haptics.tap(); dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: .white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.pressable)
                Spacer()
            }
            Text("YOUR WALK").font(.inter(10, .bold)).kerning(1.8).foregroundStyle(Nuru.gold)
                .padding(.top, 10)
            Text("Look how far He has brought you")
                .font(.fraunces(24)).foregroundStyle(.white)
            if !events.isEmpty {
                Text("\(events.count) moments, all real")
                    .font(.inter(12)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0x0F2A47), Color(hex: 0x0A1C33)],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
                .ignoresSafeArea(edges: .top)
        )
    }
}

private struct WalkNode: View {
    let event: WalkEvent
    let isFirst: Bool
    let isLast: Bool

    private var glyph: Lucide {
        switch event.kind {
        case "began": return .flag
        case "module": return .bookOpen
        case "reflection": return .penLine
        case "level": return .graduationCap
        case "certificate": return .badgeCheck
        case "verse": return .quote
        case "plan": return .bookMarked
        case "badge": return .award
        default: return .sparkle
        }
    }

    /// Certificates + passed levels glow gold; the rest walk quietly in navy.
    private var isMilestone: Bool {
        ["level", "certificate", "began"].contains(event.kind)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // The thread: a continuous gold line with one node per event.
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : Nuru.gold.opacity(0.35))
                    .frame(width: 2, height: 14)
                ZStack {
                    Circle()
                        .fill(isMilestone ? Nuru.gold : Color.white)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Nuru.gold.opacity(isMilestone ? 0 : 0.5), lineWidth: 1))
                    Icon(glyph, size: 14, color: isMilestone ? Nuru.navy : Nuru.goldChipText)
                }
                if !isLast {
                    Rectangle().fill(Nuru.gold.opacity(0.35))
                        .frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(event.dateLine)
                    .font(.inter(10, .semibold)).kerning(0.8).foregroundStyle(Nuru.ink.opacity(0.45))
                Text(event.title)
                    .font(.inter(14.5, .semibold)).foregroundStyle(Nuru.navy)
                    .fixedSize(horizontal: false, vertical: true)
                if let d = event.detail, !d.isEmpty {
                    Text(d).font(.inter(12)).foregroundStyle(Nuru.ink.opacity(0.65))
                }
                if let q = event.quote, !q.isEmpty {
                    Text("\u{201C}\(q)\u{201D}")
                        .font(.fraunces(14)).italic().foregroundStyle(Nuru.navyMid)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Nuru.gold.opacity(0.7)).frame(width: 2.5)
                        }
                        .padding(.top, 2)
                }
            }
            .padding(.bottom, 22)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Footprints on a module (reader, first page)

/// "Leah and Sam walked here before you" — overlapping avatars of cell-mates
/// who already completed this module. Renders nothing when the trail is fresh.
struct FootprintsStrip: View {
    let moduleId: String
    @State private var res: FootprintsRes?

    private var line: String? {
        guard let r = res, r.count > 0 else { return nil }
        let names = r.footprints.map(\.firstName)
        let others = r.count - names.count
        let shown: String
        switch names.count {
        case 0: return nil
        case 1: shown = names[0]
        case 2: shown = "\(names[0]) and \(names[1])"
        default: shown = names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
        if others > 0 {
            return "\(shown) and \(others) other\(others == 1 ? "" : "s") walked here before you."
        }
        return "\(shown) walked here before you."
    }

    var body: some View {
        Group {
            if let line, let r = res {
                HStack(spacing: 10) {
                    HStack(spacing: -8) {
                        ForEach(Array(r.footprints.prefix(4).enumerated()), id: \.offset) { _, f in
                            Avatar(url: f.avatarUrl, name: f.firstName, size: 26)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        }
                    }
                    Text(line)
                        .font(.inter(12)).foregroundStyle(Nuru.ink.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.7), in: Capsule())
                .overlay(Capsule().stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
            }
        }
        .task { res = try? await MemberAPI.footprints(moduleId: moduleId) }
    }
}
