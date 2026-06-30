// Hard-lock gating (§1.9) — the Swift port of screens/levelGating.ts. Pure, so
// it stays trivially testable. A level above the member's current_level is
// locked: the client must never offer a path into higher-level content. The
// server stays authoritative (the API also refuses), so when the server marks a
// level "locked" we honour that too.
import Foundation

enum LevelGating {
    /// Whether a level should render as a non-tappable, dimmed locked card (§1.9).
    static func isLevelLocked(_ levelNumber: Int, currentLevel: Int, serverStatus: LevelStatus?) -> Bool {
        if serverStatus == .locked { return true }
        return levelNumber > currentLevel
    }

    /// Member-facing label on a locked level card.
    static func lockedLevelLabel(currentLevel: Int) -> String {
        "Complete Level \(currentLevel) to unlock"
    }
}
