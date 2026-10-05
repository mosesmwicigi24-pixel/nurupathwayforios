// The parts of a plan day (pathway docs/EXPERIENCE.md §7.4 #2, #4) — ONE
// grouping for the day hub's rows, the plan page's "1 part left" and the
// Plans streak card's "Today: 2 of 3 parts", so the three never count a day
// differently. Pure: no views, no network; the tests pin it. Android groups
// the same way: each Watch / Listen alone · The Word (Scripture, teaching,
// Go Deeper) · Respond (the prayer) · Talk it Over — and a part is done when
// every one of its segments is.
import Foundation

enum PlanDayParts {
    enum Kind: Equatable { case media, word, respond, talk }

    struct Part: Equatable {
        /// The media segment's own id, else "word" / "respond" / "talk".
        let id: String
        let kind: Kind
        let segments: [PlanSegment]
        /// Where the part starts in `ordered(_:)` — the reader's index.
        let firstIndex: Int
    }

    /// The study flow: watch/listen first (media sets the scene), then the
    /// Word (Scripture), the teaching, Talk it Over, the prayer, and Go
    /// Deeper for the hungry.
    static func rank(_ s: PlanSegment) -> Int {
        switch s.kind.lowercased() {
        case "video", "audio": return 0
        case "scripture": return 1
        case "talk": return 3
        case "reading": return 5
        default: return s.title.lowercased().hasPrefix("pray") ? 4 : 2   // Pray after Talk; teaching before
        }
    }

    /// The segments in study order — stable within a rank (the authored sort
    /// breaks ties).
    static func ordered(_ segments: [PlanSegment]) -> [PlanSegment] {
        segments.sorted { rank($0) == rank($1) ? $0.sort < $1.sort : rank($0) < rank($1) }
    }

    /// The day's parts in the hub's order: each video or audio alone, then
    /// The Word, Respond, and Talk it Over (the family's conversation stands
    /// alone).
    static func parts(_ segments: [PlanSegment]) -> [Part] {
        let segs = ordered(segments)
        var out: [Part] = []
        for (i, s) in segs.enumerated() where rank(s) == 0 {
            out.append(Part(id: s.segmentId, kind: .media, segments: [s], firstIndex: i))
        }
        let groups: [(id: String, kind: Kind, ranks: Set<Int>)] = [
            ("word", .word, [1, 2, 5]), ("respond", .respond, [4]), ("talk", .talk, [3]),
        ]
        for (id, kind, ranks) in groups {
            let hit = segs.enumerated().filter { ranks.contains(rank($0.element)) }
            if let first = hit.first {
                out.append(Part(id: id, kind: kind, segments: hit.map(\.element), firstIndex: first.offset))
            }
        }
        return out
    }

    /// Parts done of all. `alsoDone`: segments finished this session, ahead
    /// of the next fetch.
    static func progress(_ segments: [PlanSegment], alsoDone: Set<String> = []) -> (done: Int, total: Int) {
        let all = parts(segments)
        let done = all.filter { p in p.segments.allSatisfy { $0.completed || alsoDone.contains($0.segmentId) } }
        return (done.count, all.count)
    }

    /// The pill on the day the member is on, on the plan's page (§7.4 #2):
    /// "1 part left" once the day is begun, "Start" before.
    static func pill(_ segments: [PlanSegment]) -> String {
        let p = progress(segments)
        let left = p.total - p.done
        guard p.done > 0, left > 0 else { return "Start" }
        return left == 1 ? "1 part left" : "\(left) parts left"
    }

    /// The plan page's gold button (§7.4 #2): "Begin Day 1" until anything of
    /// the plan is done — a day, or any part of one; then "Continue · Day N",
    /// the day the member is on; "Read again" once every day is done.
    static func planButton(_ d: ReadingPlanDetail) -> String {
        let finished = d.days.filter { $0.completed == true }.count
        if !d.days.isEmpty && finished >= d.days.count { return "Read again" }
        let begun = finished > 0 || d.days.contains { ($0.segments ?? []).contains(where: \.completed) }
        return begun ? "Continue · Day \(d.continueDay?.dayNumber ?? 1)" : "Begin Day 1"
    }
}
