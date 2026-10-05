// Whether the member has a discipler — the one truth every offer of a
// discipler reads (EXPERIENCE.md Cycle 4, B1). The walk found the discipler
// offered in five places to a member who has none ("Meet your discipler",
// "Your Discipleship Hub", the level page's "A discipler will walk with you ·
// Chat" and its floating "Message", Community's "My Discipler"), each opening
// onto "No discipler yet". Every one now asks GET /growth/mentor, through
// here, and shows itself only when the server names a discipler.
import SwiftUI

@MainActor
final class DisciplerStore: ObservableObject {
    static let shared = DisciplerStore()

    /// The paired discipler, as GET /growth/mentor answers. Nil = none, or not
    /// known yet: an offer of a discipler waits for the server to name one.
    @Published private(set) var mentor: MentorInfo.Mentor?
    /// The server has answered at least once this session.
    @Published private(set) var known = false
    private var inFlight = false

    var hasDiscipler: Bool { mentor != nil }

    /// Pure, so the rule is pinned by tests: an offer shows only for a
    /// discipler the server named.
    nonisolated static func offers(_ mentor: MentorInfo.Mentor?) -> Bool { mentor != nil }

    /// Re-reads the pairing. A failed read keeps the last answer — a dropped
    /// connection never invents a discipler, nor takes a real one away.
    func refresh() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        if let info = try? await MemberAPI.mentor() {
            mentor = info.mentor
            known = true
        }
    }

    /// Answers already in hand from a screen that read /growth/mentor itself.
    func record(_ mentor: MentorInfo.Mentor?) {
        self.mentor = mentor
        known = true
    }

    /// Signed out: the next member starts with nobody's discipler.
    func reset() {
        mentor = nil
        known = false
    }
}
