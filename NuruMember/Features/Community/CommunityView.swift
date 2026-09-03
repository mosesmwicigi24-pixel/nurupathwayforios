// Community — one place to be with people.
//
// Phase 3 of the Partners & Community design (approved 2026-09-02), steps 1
// and 2 only. Before this, community life was scattered across three hosts:
// conversations in a "Chat" segment under You, prayer behind Home tiles,
// discussions behind Home tiles. This gives the segment the name Community and
// two doors — Talk and Pray. Discussions stay on Home for now, and "Together"
// (the cell-based feed) is Phase 4.
//
// RESTRUCTURING ONLY. Nothing behind either door changes: Talk IS ChatView,
// Pray IS PrayerRoomView. Both are mounted lazily, exactly as YouTabView
// mounts its segments, so Pray pays no load cost until someone opens it.
//
// The deep-link surface is deliberately untouched. The You segment keeps its
// `.chat` case and its "chat" route string, and every CommunityRoute below
// keeps its name and payload — prayer notifications and shortcuts land where
// they always did.
import SwiftUI

enum CommunityRoute: Hashable {
    case prayerWall
    case prayer(String)      // postId
    case discussions
    case discussion(String)  // threadId
}

enum CommunityDoor: Hashable, CaseIterable {
    case talk, pray

    var label: String {
        switch self {
        case .talk: return "Talk"
        case .pray: return "Pray"
        }
    }
    var icon: Lucide {
        switch self {
        case .talk: return .messageCircle
        case .pray: return .handHeart
        }
    }
}

struct CommunityView: View {
    var embeddedInYou: Bool = false
    @ObservedObject private var chatBadge = ChatBadge.shared
    @State private var door: CommunityDoor = .talk
    /// Lazily mounted, like YouTabView's segments: the Prayer Room does not
    /// load until someone actually opens that door.
    @State private var mounted: Set<CommunityDoor> = [.talk]

    var body: some View {
        VStack(spacing: 0) {
            doorRow
            ZStack {
                ForEach(CommunityDoor.allCases, id: \.self) { d in
                    if mounted.contains(d) {
                        content(d)
                            .opacity(door == d ? 1 : 0)
                            .allowsHitTesting(door == d)
                    }
                }
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
    }

    @ViewBuilder private func content(_ d: CommunityDoor) -> some View {
        switch d {
        case .talk: ChatView(embeddedInYou: embeddedInYou)
        case .pray: PrayerRoomView()
        }
    }

    // MARK: - The two doors
    //
    // A quieter echo of the You capsule one level up: the same pill idiom,
    // smaller, left-aligned, so the eye reads it as "within Community" rather
    // than as a second row of top-level tabs.

    private var doorRow: some View {
        HStack(spacing: 6) {
            ForEach(CommunityDoor.allCases, id: \.self) { d in
                doorButton(d)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.vertical, 8)
        .background(Nuru.paper)
    }

    private func doorButton(_ d: CommunityDoor) -> some View {
        let selected = door == d
        // Unread rides the Talk door only — a quiet chip, matching the chips
        // Chat already uses for its own segments.
        let count = d == .talk ? chatBadge.count : 0
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                mounted.insert(d)
                door = d
            }
        } label: {
            HStack(spacing: 5) {
                Icon(d.icon, size: 11, color: selected ? Nuru.gold : Color(hex: 0x59667C))
                Text(d.label).font(.inter(12, .semibold))
                    .foregroundStyle(selected ? Color.white : Color(hex: 0x59667C))
                if count > 0 {
                    Text(count > 9 ? "9+" : "\(count)").font(.inter(10, .bold))
                        .foregroundStyle(selected ? Nuru.navy : Color(hex: 0x6A7686))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .frame(minWidth: 18)
                        .background(selected ? Nuru.gold : Nuru.surface, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color.white.opacity(0.7)),
                in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
