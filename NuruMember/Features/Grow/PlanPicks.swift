// The Plans tab's picks (pathway docs/EXPERIENCE.md §8.2 #6) — one rule over
// the same inputs on both apps, so the same member sees the same plans on the
// same day. Pure (no views, no network); the tests pin it, and Android's
// ReadingPlansScreen follows the same steps:
//
// • The hero: the server's promos (GET /growth/plans/promos) in the server's
//   order, each joined to the catalogue the page holds — a promo whose plan
//   isn't there is dropped, a plan is never promoted twice — and the first
//   one leads, with the server's kicker ("FOR YOU" if it ever sent none).
// • PLAN OF THE DAY (no promo to show): the first plan in the server's order
//   (GET /growth/plans, never re-sorted) the member hasn't started; else the
//   first plan.
// • The mid-page promo (no server promos): the plans in the server's order
//   that are not started, not the plan of the day and carry a description;
//   the pick is pool[(D / 2) % pool.count], where D is the day number on the
//   church's calendar — whole days from 1970-01-01 to today in Africa/Nairobi
//   (Android: LocalDate.now(ZoneId.of("Africa/Nairobi")).toEpochDay()).
//   2026-10-05 is D = 20731. It used to be the UTC day, which turns at 03:00
//   in Nairobi.
import Foundation

enum PlanPicks {
    /// PLAN OF THE DAY — the first plan not started, in the server's order.
    static func planOfDay(_ plans: [ReadingPlanRow]) -> ReadingPlanRow? {
        plans.first { !$0.enrolled } ?? plans.first
    }

    /// Whole days from 1970-01-01 to `now`'s date on the Nairobi calendar.
    static func nairobiDay(_ now: Date = Date()) -> Int {
        let offset = Double(GiveCalendar.nairobi.secondsFromGMT(for: now))
        return Int(((now.timeIntervalSince1970 + offset) / 86_400).rounded(.down))
    }

    /// The mid-page promo for day `day` — never the plan of the day, never one
    /// being read, only a plan whose own words can carry a promo.
    static func midPromo(_ plans: [ReadingPlanRow], planOfDayId: String?, day: Int) -> ReadingPlanRow? {
        let pool = plans.filter { !$0.enrolled && $0.planId != planOfDayId && ($0.description?.isEmpty == false) }
        guard !pool.isEmpty else { return nil }
        let i = (day / 2) % pool.count
        return pool[i < 0 ? i + pool.count : i]
    }

    /// A server promo joined to the plan it names.
    struct Resolved: Identifiable {
        let promo: PlanPromo
        let plan: ReadingPlanRow
        var id: String { promo.slot + "\u{00B7}" + promo.planId }
        /// The gold capsule's words — never blank.
        var kicker: String {
            let k = promo.kicker.trimmingCharacters(in: .whitespaces)
            return k.isEmpty ? "FOR YOU" : k
        }
    }

    /// The server's promos, in its order, joined to the plans the page holds.
    static func resolve(_ promos: [PlanPromo], in plans: [ReadingPlanRow]) -> [Resolved] {
        guard !promos.isEmpty, !plans.isEmpty else { return [] }
        let byId = Dictionary(plans.map { ($0.planId, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        return promos.compactMap { p in
            guard let plan = byId[p.planId], seen.insert(plan.planId).inserted else { return nil }
            return Resolved(promo: p, plan: plan)
        }
    }
}
