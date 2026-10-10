// Community — one place to be with people.
//
// Phase 3 of the Partners & Community design (approved 2026-09-02) gave the
// You segment the name Community. It had two doors — Talk and Pray — in a
// switch of their own, between You's segment bar and the inbox's chips: three
// switchers stacked (EXPERIENCE.md §9.2 #13). Now Community IS its talk
// (ChatView), the chips are its one switcher, and Pray is a door inside it —
// "My Prayer Room" — opening the prayer room's own page.
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

struct CommunityView: View {
    var embeddedInYou: Bool = false

    /// Community is its talk: ChatView, whose chips (My Space · Chat · My
    /// Discipler · My Pastor) are its one switcher under You's segment bar
    /// (EXPERIENCE.md §9.2 #13). The Talk | Pray row that stood between them
    /// is gone; Pray is a door inside — "My Prayer Room" — opening the prayer
    /// room's own page. Android's a3a901f.
    var body: some View {
        ChatView(embeddedInYou: embeddedInYou)
            .background(Nuru.paper.ignoresSafeArea())
    }
}
