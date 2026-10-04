// One bell (pathway docs/EXPERIENCE.md §7.2 #4, §7.1 rule 8: signals tell the
// truth). Every tab's header carries the same bell: it opens the inbox, and
// one gold dot shows only while the inbox has something unread. The dots used
// to be painted on (Events, Plans, Give, Pathway), the Pathway bell opened
// nothing, Home showed a count, and Chat's lit up for chat messages — four
// signals, none of them the inbox's. Now there is one count, InboxBadge, and
// every bell reads it. Each header keeps its own bell's size and tile.
import SwiftUI

/// The inbox's unread count (GET /me/notifications → `unread`) — the one
/// number behind every bell's dot, as the app icon's badge is. Refreshed on
/// foreground (LocalNotifier.sync), when the inbox closes, after marking read,
/// and with Home's own load. Reads are ticketed: an answer that left before a
/// newer one never overwrites it when it lands late.
@MainActor
final class InboxBadge: ObservableObject {
    static let shared = InboxBadge()

    @Published private(set) var unread = 0
    /// Tickets handed out (reads started, local truths set), and the newest
    /// one whose count is on screen.
    private var issued = 0
    private var landed = 0

    private init() {}

    /// The dot shows only while something is unread. Pure.
    nonisolated static func showsDot(unread: Int) -> Bool { unread > 0 }

    /// Re-reads the count. A failed read keeps what the dot already knew.
    func refresh() async {
        let t = ticket()
        guard let n = try? await MemberAPI.unreadNotifications() else { return }
        land(n, ticket: t)
    }

    /// For a caller that reads the count itself: take a ticket BEFORE the
    /// read, land the answer with it.
    func ticket() -> Int {
        issued += 1
        return issued
    }

    func land(_ n: Int, ticket: Int) {
        guard ticket > landed else { return }   // a newer answer is already on screen
        landed = ticket
        unread = max(0, n)
    }

    /// What the member just did, known before the server says it (the inbox
    /// marking a notice read) — newer than any read still in flight.
    func set(_ n: Int) { land(n, ticket: ticket()) }

    /// Signed out: nobody's dot.
    func reset() { set(0) }
}

/// The bell — the inbox's one door on every tab. `Look` keeps each header's
/// own size and tile; the link and the dot are the same everywhere. Every
/// stack that shows one registers AppRoute (`nuruDestinations()`, or
/// `inboxDestinations()` where a stack registers its own routes).
struct NuruBell: View {
    struct Look {
        var size: CGFloat
        /// A circle, or the rounded tile (16pt corners).
        var circle: Bool
        var iconSize: CGFloat
        var iconColor: Color
        var fill: Color
        var stroke: Color
    }

    let look: Look
    @ObservedObject private var badge = InboxBadge.shared

    init(look: Look) { self.look = look }

    private var shape: AnyShape {
        look.circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private var dot: Bool { InboxBadge.showsDot(unread: badge.unread) }

    var body: some View {
        NavigationLink(value: AppRoute.notifications) {
            Icon(.bell, size: look.iconSize, color: look.iconColor)
                .frame(width: look.size, height: look.size)
                .background(look.fill, in: shape)
                .overlay(shape.stroke(look.stroke, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if dot {
                        Circle().fill(Nuru.gold).frame(width: 8, height: 8)
                            .shadow(color: Nuru.gold.opacity(0.8), radius: 3)
                            // On the rim, whatever the bell's size or tile.
                            .padding(look.size * 0.2)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: dot)
        }
        .buttonStyle(.pressable)
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        .accessibilityLabel(dot ? "Notifications, \(badge.unread) unread" : "Notifications")
    }
}
