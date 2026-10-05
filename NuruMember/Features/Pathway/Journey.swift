// The member's journey state (pathway docs/EXPERIENCE.md §3) — ONE derivation
// from GET /me/pathway (the CURRENT level's row) and that level's module trail,
// read by every surface that says where the member is: Home's pill, continue
// card and progress line; Pathway's hero card, ring and summit. Two cards
// never tell two stories because there is only one story, told here.
//
// Modules a member earns alone; levels need a human discipler to usher them
// in — so after "every module is done" comes the exam, and after the exam, a
// person. Pure (no views, no network): both tabs and the tests read the same
// words, and Android says the same words from the same table.
import Foundation

struct Journey: Equatable {
    enum Stage: Equatable {
        /// The current level is open — modules to walk (or none published yet).
        case learning
        /// Every module is done and the level's exam can be taken (published,
        /// with questions — `exam_available`).
        case examReady
        /// Every module is done; the exam is still in review, or published
        /// with no questions yet — nothing to take, so nothing is offered.
        case examSoon
        /// The exam is passed — the member's leader opens the next level.
        case awaitingUsher
        /// The final level's exam is passed: commissioned.
        case finished
    }

    /// Where the next step's action lands — the Pathway tab's own routes.
    enum Destination: Equatable {
        case module(String)   // moduleId
        case exam(Int)        // levelNumber
        case level(Int)       // levelNumber
        case walk             // Your Walk — the whole journey

        var route: PathwayRoute {
            switch self {
            case .module(let id): return .module(id)
            case .exam(let n): return .exam(n)
            case .level(let n): return .level(n)
            case .walk: return .walk
            }
        }
    }

    let stage: Stage
    /// The member's current level, N.
    let levelNumber: Int
    let levelTitle: String
    /// X of Y — the current level's modules as the member reads them: its
    /// LESSONS (`lessons_completed` / `lessons_total`; the module counts from
    /// an older server). The exam is its own step, never "a module"
    /// (EXPERIENCE.md §8.2 #4) — so a finisher reads "20 of 20", never "20 of 21".
    let completedModules: Int
    let totalModules: Int
    /// Journey progress in LEVELS, 0…1 (1 only at the summit): (levels before
    /// the current + the current level's fraction) / all levels. Never a share
    /// of published modules — Levels 2–6 with nothing published yet must not
    /// make Level 1's twenty modules read as the whole road.
    let progress: Double

    /// The header pill: "3 of 10 modules", "Exam ready", "Commissioned"…
    let pill: String
    /// The next step — kicker, title, line and (when there is one) action.
    let kicker: String
    let title: String
    let line: String
    let actionLabel: String?
    let destination: Destination?

    /// The summit celebration fires here and nowhere else.
    var summitReached: Bool { stage == .finished }
    /// Whole percent of the journey — 100 only at the summit: with the last
    /// exam still ahead the ring reads 99 at most.
    var progressPercent: Int {
        stage == .finished ? 100 : min(99, Int((min(1, max(0, progress)) * 100).rounded()))
    }
    /// The current level's bar, 0…100 — whole once every module is done.
    var levelPercent: Int {
        guard stage == .learning else { return 100 }
        guard totalModules > 0 else { return 0 }
        return min(100, Int((Double(completedModules) / Double(totalModules) * 100).rounded()))
    }

    /// Home's "Your progress" line — the bold fact, then the rest.
    var progressLine: (bold: String, rest: String) {
        if stage == .learning, totalModules > 0 {
            return ("\(completedModules) of \(totalModules) modules", " in Level \(levelNumber)")
        }
        return (title, "")
    }

    /// The goal-gradient line under a level's bar on Home's continue card —
    /// only while there are modules left; never "Almost there" at 100%.
    static func momentum(levelPercent pct: Int) -> String? {
        guard pct < 100 else { return nil }
        return pct >= 60 ? "Almost there — finish strong 🎉" : "Just \(100 - pct)% to your next badge"
    }
}

extension Journey {
    /// The journey, from the pathway summary and (when loaded) the current
    /// level's module trail — nil until there is a level to speak about.
    /// A trail for any other level is ignored.
    static func derive(_ summary: PathwaySummary?, trail: [LevelModule]? = nil) -> Journey? {
        guard let summary, !summary.levels.isEmpty else { return nil }
        let levels = summary.levels.sorted { $0.levelNumber < $1.levelNumber }
        // Ushered past the final level — beyond the road's end: commissioned.
        let pastTheEnd = summary.currentLevel > (levels.last?.levelNumber ?? 0)
        let idx = pastTheEnd ? levels.count - 1
            : levels.firstIndex { $0.levelNumber == summary.currentLevel }
                ?? levels.firstIndex { $0.status == .active }
                ?? 0
        let cur = levels[idx]
        let n = cur.levelNumber
        let isLast = idx == levels.count - 1
        let nextLevel = idx + 1 < levels.count ? levels[idx + 1].levelNumber : n + 1
        // Lessons — the exam is a step, not a module (§8.2 #4).
        let y = max(0, cur.lessonCount), x = min(max(0, cur.lessonsDone), y)

        // The trail's own exam row (prod's exit-exam module): completed = the
        // exam is passed; NEXT = every lesson done and the exam open. After the
        // final usher the summary no longer says awaiting, but this row still
        // says passed. A trail for any other level is ignored.
        let mods = (trail ?? []).filter { $0.levelNumber == n }
        let exam = mods.first { $0.isExam }
        let examPassed = exam?.completed == true
        // Without the trail (not loaded yet, or the read failed), the summary
        // says the same thing in numbers once it counts lessons apart (§8.2
        // #4): every lesson done, and an exam step counted beyond them that
        // isn't done — the server's own trail opens that exam row exactly
        // then. Else Home's first paint read "20 of 20 modules · Continue".
        let examLeft = exam == nil && cur.lessonsTotal != nil && y > 0 && x >= y
            && cur.totalModules > y && cur.completedModules < cur.totalModules
        let examOpen = exam.map { !$0.completed && $0.status == .next } ?? examLeft
        // The exam is offered only when it can be TAKEN (EXPERIENCE.md §7.2
        // #1): published AND with questions — `exam_available` on the level
        // and on the trail's exam row. A published exam with no questions
        // answered 422 behind an "Exam ready" pill. Absent (an older server)
        // reads as available, so that server behaves exactly as before.
        let examTakeable = cur.examAvailable && (exam?.examAvailable ?? true)
        // The lesson to continue — Pathway's resume rule without its old "else
        // the last one" fallback (which re-opened a finished module), and never
        // the exam row (the exam is a stage, not a lesson).
        let lessons = mods.filter { !$0.isExam }.sorted { $0.moduleSequenceNumber < $1.moduleSequenceNumber }
        let next = lessons.first { $0.status == .next && !$0.completed } ?? lessons.first { !$0.completed }

        let stage: Stage
        if pastTheEnd {
            stage = .finished
        } else if cur.isAwaitingReview || examPassed {
            stage = isLast ? .finished : .awaitingUsher
        } else if cur.status == .completed {
            stage = cur.examPublished && examTakeable ? .examReady : .examSoon
        } else if examOpen {
            // A level counting its exam row stays "active" at 20 of 21.
            stage = examTakeable ? .examReady : .examSoon
        } else {
            stage = .learning
        }

        // (levels before the current + the current level's fraction) / all
        // levels — the fraction is whole once every module is done.
        let fraction: Double = stage == .learning ? (y > 0 ? min(1, Double(x) / Double(y)) : 0) : 1
        let progress = stage == .finished ? 1 : min(1, (Double(idx) + fraction) / Double(levels.count))

        let pill: String, kicker: String, title: String, line: String
        var action: (label: String, to: Destination)?
        switch stage {
        case .learning where y == 0:
            // Ushered into a level whose modules are not published yet.
            pill = "Modules open soon"
            kicker = "Modules open soon · Level \(n)"
            title = "Level \(n) is being prepared"
            line = "Its modules open soon — we'll let you know."
        case .learning:
            let verb = x == 0 ? "Start" : "Continue"
            pill = "\(x) of \(y) modules"
            kicker = "\(verb) · Level \(n)"
            title = next?.title ?? cur.title
            line = "\(x) of \(y) modules in Level \(n)"
            // A module still behind its gate opens the level page (where the
            // member sees what stands before it) — the server would refuse it.
            if let next, next.status != .locked, !next.locked {
                action = (verb, .module(next.moduleId))
            } else {
                action = (verb, .level(n))
            }
        case .examReady:
            pill = "Exam ready"
            kicker = "Exam ready · Level \(n)"
            title = "Take the Level \(n) exam"
            line = isLast
                ? "Every module is done — the exam opens the way to being sent."
                : "Every module is done — the exam opens the way to Level \(nextLevel)."
            action = ("Begin the exam", .exam(n))
        case .examSoon:
            pill = "Exam opens soon"
            kicker = "Exam opens soon · Level \(n)"
            title = "Level \(n) complete"
            line = "Every module is done. The exam opens soon — we'll let you know."
        case .awaitingUsher:
            pill = "Exam passed"
            kicker = "Exam passed · Level \(n)"
            title = "Level \(nextLevel) is next"
            line = "You passed the Level \(n) exam. Your leader will open Level \(nextLevel) — you'll get a notice."
            action = ("See Level \(n)", .level(n))
        case .finished:
            pill = "Commissioned"
            kicker = "Commissioned"
            title = "You have been commissioned"
            line = "Sent to make disciples — Matthew 28:19"
            action = ("See your journey", .walk)
        }

        return Journey(stage: stage, levelNumber: n, levelTitle: cur.title,
                       completedModules: x, totalModules: y, progress: progress,
                       pill: pill, kicker: kicker, title: title, line: line,
                       actionLabel: action?.label, destination: action?.to)
    }
}
