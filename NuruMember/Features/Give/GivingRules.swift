// Giving Cycle 1 — the pure rules behind the Give form, kept out of the views
// so they can be tested: which number an M-Pesa prompt goes to, which rails
// the member may pick, which schedules the strip lists, and what a refused
// gift means. Money stays server-authoritative (§5.6): these rules decide only
// what the form OFFERS and SAYS — the server re-checks every one of them.
import Foundation

// MARK: - Kenyan mobile numbers

/// A Kenyan mobile number the way the SERVER reads one (backend
/// `kenyanMobileNumber`): 07XX… / 01XX…, +2547… / 2547…, +2541… / 2541…, or
/// the nine digits without the 0 — spaces, dashes, dots and brackets allowed —
/// as E.164 (+2547XXXXXXXX / +2541XXXXXXXX). Anything else is not a number an
/// M-Pesa prompt can reach, and the sheet says so before the server has to.
enum KenyanPhone {
    enum Check: Equatable {
        case empty
        case invalid
        case valid(String)      // the number as E.164
    }

    /// The line under the field for a number we cannot prompt — the server's
    /// own words (422 PHONE_REQUIRED), so the two never disagree.
    static let invalidMessage = "That doesn't look like a Kenyan mobile number. Use 07XX XXX XXX or 01XX XXX XXX."

    static func check(_ raw: String) -> Check {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        var digits = ""
        var sawPlus = false
        for ch in raw {
            if ch.isASCII && ch.isNumber { digits.append(ch) }
            else if ch == "+" && !sawPlus && digits.isEmpty { sawPlus = true }
            else if !isSeparator(ch) { return .invalid }
        }
        if digits.hasPrefix("0") { digits = "254" + digits.dropFirst() }
        else if digits.count == 9, digits.hasPrefix("7") || digits.hasPrefix("1") { digits = "254" + digits }
        guard digits.count == 12, digits.hasPrefix("2547") || digits.hasPrefix("2541") else { return .invalid }
        return .valid("+" + digits)
    }

    /// The number as E.164, or nil when it is not a Kenyan mobile number.
    static func normalize(_ raw: String) -> String? {
        if case let .valid(e164) = check(raw) { return e164 }
        return nil
    }

    /// Spaces (any kind), dashes, dots and brackets — and the invisible
    /// direction marks iOS wraps around a number copied from Contacts.
    private static func isSeparator(_ ch: Character) -> Bool {
        if ch.isWhitespace || "-.()".contains(ch) { return true }
        return ch.unicodeScalars.allSatisfy { $0.properties.generalCategory == .format }
    }
}

// MARK: - The number a prompt goes to

/// The number each member last gave from ON THIS DEVICE (UserDefaults
/// `giving.lastPhone`, keyed by member id). Keyed so a shared phone never
/// offers one member's number to another — the hardcoded-number bug this
/// replaced, one account over.
struct GivingPhoneMemory {
    static let key = "giving.lastPhone"
    var defaults: UserDefaults = .standard

    func phone(for userId: String?) -> String? {
        guard let userId, !userId.isEmpty,
              let saved = (defaults.dictionary(forKey: Self.key) as? [String: String])?[userId] else { return nil }
        return KenyanPhone.normalize(saved)
    }

    /// Remembers the number the server just accepted a gift for. Only a real
    /// Kenyan mobile number is kept, always as E.164.
    func remember(_ phone: String, for userId: String?) {
        guard let userId, !userId.isEmpty, let e164 = KenyanPhone.normalize(phone) else { return }
        var saved = (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
        saved[userId] = e164
        defaults.set(saved, forKey: Self.key)
    }

    /// The number the prompt goes to before the member types one: the one
    /// they last gave from here, else the one on their profile (the server's
    /// `phone_on_file`), else none — and the sheet asks for it. Never a
    /// number that is not theirs.
    static func initial(remembered: String?, onFile: String?) -> String? {
        remembered.flatMap(KenyanPhone.normalize) ?? onFile.flatMap(KenyanPhone.normalize)
    }
}

// MARK: - Rails the member may pick

enum GivingRails {
    /// Rails this build can carry a gift through end to end. A card needs the
    /// Stripe SDK (client-side tokenisation, SAQ-A §5.6), which the app does
    /// not have — so a card rail stays SOON here even on a server that could
    /// take one (a dev server does).
    static let appCanComplete: Set<String> = ["mpesa", "airtel", "paypal"]

    /// The member's own order for the rails still offered, then any rail the
    /// server newly lists, in the server's order. A rail it no longer lists
    /// drops out.
    static func mergedOrder(current: [String], server: [String]) -> [String] {
        let offered = Set(server)
        var seen = Set<String>()
        var out: [String] = []
        for k in current where offered.contains(k) && seen.insert(k).inserted { out.append(k) }
        for k in server where seen.insert(k).inserted { out.append(k) }
        return out
    }
}

extension GivingMethods {
    func method(_ key: String) -> GivingMethod? { methods.first { $0.key == key } }

    /// The rail's own currency — M-Pesa KES, PayPal USD; KES when it names
    /// none (a card takes any).
    func currency(_ key: String) -> String { (method(key)?.currency ?? "KES").uppercased() }

    /// The member may pick it HERE: the server says it takes money, and this
    /// build can carry a gift through it. `onlyCurrency` — paying a pledge or
    /// need, whose currency decides the rails (Giving Cycle 5: the server
    /// refuses any other, 422 CURRENCY_MISMATCH) — leaves out the rest.
    func isSelectable(_ key: String, onlyCurrency: String? = nil) -> Bool {
        guard (method(key)?.enabled ?? false), GivingRails.appCanComplete.contains(key) else { return false }
        return onlyCurrency.map { currency(key) == $0.uppercased() } ?? true
    }

    /// The rails the form lists: all of them, or — paying a pledge or need —
    /// those in its currency (a KES pledge: M-Pesa; a USD one: PayPal).
    func offered(onlyCurrency: String? = nil) -> [GivingMethod] {
        guard let cur = onlyCurrency?.uppercased() else { return methods }
        return methods.filter { currency($0.key) == cur }
    }

    /// Why nothing can be picked for something in `currency` (a USD pledge
    /// while PayPal is off): "Gifts toward this are in US dollars — PayPal
    /// giving is coming soon."
    func unavailableNote(forCurrency currency: String) -> String {
        let words = GiveMoney.currencyWords(currency)
        guard let rail = offered(onlyCurrency: currency).first else {
            return "Gifts toward this are in \(words), and there's no way to give in \(words) here yet."
        }
        return "Gifts toward this are in \(words) — \(unavailableNote(rail.key))"
    }

    /// A weekly / monthly gift may run on it — the server's word (M-Pesa only
    /// today), and only on a rail the member can pick at all.
    func allowsRecurring(_ key: String) -> Bool {
        isSelectable(key) && (method(key)?.recurring ?? false)
    }

    /// The rail the form should have selected: the current one while it is
    /// still selectable, else the server's default, else the first selectable
    /// one — nil when none is (Give then says why instead of sending).
    func selection(keeping current: String, onlyCurrency: String? = nil) -> String? {
        if isSelectable(current, onlyCurrency: onlyCurrency) { return current }
        if let d = defaultMethod, isSelectable(d, onlyCurrency: onlyCurrency) { return d }
        return methods.first { isSelectable($0.key, onlyCurrency: onlyCurrency) }?.key
    }

    /// The footer's promise names only rails that can take money here
    /// (Giving Cycle 2: it said "M-Pesa & card" while cards could not):
    /// "Secure · M-Pesa · Receipt sent instantly".
    func secureNote() -> String {
        let names = methods.filter { isSelectable($0.key) }
            .map { $0.label.isEmpty ? givingMethodName($0.key) : $0.label }
        return names.isEmpty ? "Secure · Receipt sent instantly"
                             : "Secure · \(names.joined(separator: " & ")) · Receipt sent instantly"
    }

    /// The chip on a rail that cannot be picked: SOON for one that is coming
    /// (the server's `coming_soon`, or one this build cannot complete yet),
    /// UNAVAILABLE for one switched off on this server. Nil when selectable.
    func unavailableBadge(_ key: String) -> String? {
        guard !isSelectable(key) else { return nil }
        guard let m = method(key), m.enabled else {
            return method(key)?.unavailableReason == "coming_soon" ? "SOON" : "UNAVAILABLE"
        }
        return "SOON"   // enabled on the server, not in this build (a card)
    }

    /// What Give says when the selected rail cannot take a gift here.
    func unavailableNote(_ key: String) -> String {
        let name = method(key).map { $0.label.isEmpty ? givingMethodName(key) : $0.label } ?? givingMethodName(key)
        return unavailableBadge(key) == "SOON"
            ? "\(name) giving is coming soon."
            : "\(name) isn't available for giving right now."
    }
}

// MARK: - ACTIVE SCHEDULES

enum GiveSchedules {
    /// What Give lists under ACTIVE SCHEDULES: running schedules, then paused
    /// ones (labelled Paused, so the member can see why and resume) — never a
    /// cancelled one, which is history rather than a schedule. A status this
    /// build does not know stays out too.
    static func listed(_ all: [GivingSchedule]) -> [GivingSchedule] {
        all.filter { $0.status.lowercased() == "active" } + all.filter { $0.status.lowercased() == "paused" }
    }
}

// MARK: - A refused gift

/// What Give does with an error from POST /giving/intents or /giving/schedules.
enum GiveRefusal: Equatable {
    /// 409 GIFT_IN_PROGRESS: the member's prompt from a moment ago is still on
    /// their phone, and a second would fail as "busy" — watch THAT one.
    case promptWaiting(transactionId: String, message: String)
    /// Anything else: the server's member-facing `message` as-is (the 422
    /// METHOD_UNAVAILABLE / METHOD_CURRENCY / AMOUNT_OUT_OF_RANGE /
    /// PHONE_REQUIRED and 409 SCHEDULE_EXISTS among them), else `fallback`.
    case message(String)

    static func from(_ error: Error, fallback: String) -> GiveRefusal {
        guard let api = error as? APIError else { return .message(fallback) }
        if case let .http(_, code, message, details) = api, code == "GIFT_IN_PROGRESS",
           let tx = details?.transactionId {
            return .promptWaiting(transactionId: tx, message: message)
        }
        return .message(api.errorDescription ?? fallback)
    }

    /// The words to show the member, whichever it is.
    var message: String {
        switch self {
        case let .promptWaiting(_, text), let .message(text): return text
        }
    }

    /// True when an attempt got NO server answer (offline, timeout,
    /// transport) — the only case in which the same idempotency key may be
    /// sent again: the server returns what it already made for a replayed
    /// key, so a lost reply never becomes a second prompt.
    static func gotNoServerAnswer(_ error: Error) -> Bool {
        if let api = error as? APIError { return api.isNetwork }
        return error is URLError
    }
}

// MARK: - Try again (Giving Cycle 3)

/// "Try again" on a failed result: the failed GIFT is retried by the server
/// (POST /giving/transactions/{id}/retry) with everything it carried — fund,
/// amount, currency, pledge or need, name, fee cover — so a retry can never
/// quietly lose its pledge. A refusal that made no gift has nothing to retry:
/// the member goes back to the form with the amount and fund kept.
enum GiveRetry {
    enum Action: Equatable {
        case retry(transactionId: String)
        case backToForm
    }

    static func action(failedTransactionId: String?) -> Action {
        guard let tx = failedTransactionId, !tx.isEmpty else { return .backToForm }
        return .retry(transactionId: tx)
    }

    /// Which failed gift "Try again" retries after a retry attempt errored:
    /// the same one while the server never answered; none after the server
    /// refused (the same request would be refused again) — then it is the
    /// form's turn.
    static func target(after error: Error, retrying transactionId: String) -> String? {
        GiveRefusal.gotNoServerAnswer(error) ? transactionId : nil
    }

    /// The idempotency key the next retry sends: the same one only when the
    /// last attempt got no server answer (so a retry that did land is found,
    /// not doubled); a fresh one after any answer, and after success (`nil`).
    static func key(after error: Error?, current: String, fresh: () -> String = { UUID().uuidString }) -> String {
        if let error, GiveRefusal.gotNoServerAnswer(error) { return current }
        return fresh()
    }
}

// MARK: - Giving notifications (Giving Cycle 3)

/// Where a giving notification lands on the Give tab. (Any other giving_*
/// notice — a receipt, the heads-up before a prompt — opens Give itself.)
enum GiveLink: Equatable {
    /// `giving_gift_failed` — that gift's result: why, what to do, Try again.
    case failedGift(transactionId: String)
    /// `giving_schedule_failed` / `giving_schedule_paused` (Giving Cycle 4) —
    /// that recurring gift's sheet: why, and Resume / Change / Pause.
    case schedule(scheduleId: String)

    static func from(template: String, transactionId: String?, scheduleId: String? = nil) -> GiveLink? {
        if template == "giving_gift_failed", let tx = transactionId, !tx.isEmpty { return .failedGift(transactionId: tx) }
        if template == "giving_schedule_failed" || template == "giving_schedule_paused",
           let id = scheduleId, !id.isEmpty { return .schedule(scheduleId: id) }
        return nil
    }
}

/// Where a Partners notice lands (Giving Cycle 5): the pledge it is about —
/// the pledge_* notices and the pledge collector's (`giving_schedule_covered`,
/// `giving_schedule_stopped`), routed by their `pledge_id`. Nil without one.
enum PledgeLink {
    static let collectorTemplates: Set<String> = ["giving_schedule_covered", "giving_schedule_stopped"]

    static func from(template: String, pledgeId: String?) -> String? {
        guard let id = pledgeId, !id.isEmpty else { return nil }
        return template.hasPrefix("pledge_") || collectorTemplates.contains(template) ? id : nil
    }
}

/// The words on a giving notification — the server's push copy
/// (workers/dispatch.ts), so the banner, the inbox and Android agree. Nil for
/// a template this has no words for (the caller's own fallback applies).
/// Checked BEFORE a payload's `title`: on the Partners notices that key is
/// the pledge's name, not a push title.
enum GivingNotificationCopy {
    static func title(template: String, payload: NotifPayload?) -> String? {
        let frequency = payload?.frequency?.lowercased()
        switch template {
        case "giving_gift_failed": return "Your gift didn't go through"
        // Giving Cycle 4 — the recurring gift's notices.
        case "giving_schedule_heads_up": return "Your \(frequency == "weekly" ? "weekly" : "monthly") gift is ready"
        case "giving_schedule_failed":
            let kind = frequency == "weekly" ? "weekly" : frequency == "monthly" ? "monthly" : "recurring"
            return "Your \(kind) gift didn't go through"
        case "giving_schedule_paused": return "Your recurring gift is paused"
        // Giving Cycle 5 — the pledge collector, and the pledge's own notices.
        case "giving_schedule_covered": return "Nothing to pay this \(frequency == "weekly" ? "week" : "month")"
        case "giving_schedule_stopped":
            switch payload?.reason {
            case "pledge_fulfilled": return "Your pledge is complete"
            case "pledge_ended": return "Your pledge has ended"
            default: return "Automatic prompts stopped"
            }
        case "pledge_due_soon":
            let days = payload?.daysAway
            let when = days == 0 ? "due today" : days == 1 ? "due tomorrow" : "due in \(days.map(String.init) ?? "a few") days"
            return "\(nonEmpty(payload?.title) ?? "Your pledge") — \(when)"
        case "pledge_overdue": return "A gentle nudge on \(nonEmpty(payload?.title) ?? "your pledge")"
        case "pledge_reminder_manual": return "From the church office: \(nonEmpty(payload?.title) ?? "your pledge")"
        case "pledge_fulfilled": return "Pledge fulfilled — thank you"
        case "pledge_claim_confirmed": return "Your payment is recorded"
        case "pledge_claim_rejected": return "We couldn't match that payment"
        default: return nil
        }
    }

    static func body(template: String, payload: NotifPayload?) -> String? {
        let amount = GiveMoney.format(payload?.amountMinor ?? 0, payload?.currency)
        let pledgeName = nonEmpty(payload?.title).map { "\u{201C}\($0)\u{201D}" }
        switch template {
        case "giving_gift_failed":
            return "\(nonEmpty(payload?.reason) ?? "The payment didn't complete.") \(nonEmpty(payload?.hint) ?? "Open Give to try again.")"
        case "giving_schedule_heads_up":
            // A pledge's collector asking only the rest (Giving Cycle 5).
            if payload?.partial == true, let pledge = nonEmpty(payload?.pledgeTitle) {
                return "An M-Pesa prompt for \(amount) — the rest of what's due on \u{201C}\(pledge)\u{201D} — is coming to your phone in a few minutes. Enter your PIN to give."
            }
            return "An M-Pesa prompt for \(amount) to \(nonEmpty(payload?.fundName) ?? "the church") is coming to your phone in a few minutes. Enter your PIN to give."
        case "giving_schedule_covered":
            let through = nonEmpty(payload?.coveredThrough).map { " through \(dayWords($0))" } ?? ""
            return "\(pledgeName ?? "Your pledge") is already paid\(through), so no M-Pesa prompt is coming this time. Thank you."
        case "giving_schedule_stopped":
            let pledge = pledgeName ?? "Your pledge"
            switch payload?.reason {
            case "pledge_fulfilled":
                return "\(pledge) is fulfilled, so its automatic M-Pesa prompts have stopped. Thank you for carrying it through."
            case "pledge_ended":
                let on = nonEmpty(payload?.untilOn).map { " on \(dayWords($0))" } ?? ""
                return "\(pledge) ended\(on), so its automatic prompts have stopped. Open Partners to make a new pledge."
            default:
                return "\(pledge) was cancelled, so its recurring gift has stopped too."
            }
        case "pledge_due_soon":
            return "\(amount) toward your pledge. Open Partners to give, or to pause it if this month is tight."
        case "pledge_overdue":
            return "\(amount) was due on \(nonEmpty(payload?.dueOn).map(dayWords) ?? "the due date"). No pressure — give when you can, or tell us if you paid another way."
        case "pledge_reminder_manual":
            return nonEmpty(payload?.message) ?? "A reminder that \(amount) toward your pledge is waiting. Thank you for standing with us."
        case "pledge_fulfilled":
            let stopped = payload?.scheduleStopped == true ? " Its automatic prompts have stopped." : ""
            return "You completed your \(nonEmpty(payload?.title) ?? "pledge"). Every shilling carried someone further.\(stopped) Open Partners to see it."
        case "pledge_claim_confirmed":
            return "\(amount) toward \(nonEmpty(payload?.title) ?? "your pledge") has been confirmed by the office. Thank you."
        case "pledge_claim_rejected":
            return "The office could not find \(amount) toward \(nonEmpty(payload?.title) ?? "your pledge"). Reply in Community or give again from Partners."
        case "giving_schedule_failed":
            let next = nonEmpty(payload?.retryAt) != nil
                ? "We'll send the prompt once more later today."
                : nonEmpty(payload?.hint) ?? "Open Give to give now or check your number."
            return "\(nonEmpty(payload?.reason) ?? "We couldn't collect it this time.") \(next)"
        case "giving_schedule_paused":
            let why = nonEmpty(payload?.reason).map { "\($0) " } ?? ""
            return "\(why)We've stopped sending prompts for now. Open Give to resume it whenever you're ready."
        default: return nil
        }
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// "5 October" for a YYYY-MM-DD date, as given — no time-zone math (the
    /// server's dayWords); the text itself when it is not one.
    static func dayWords(_ ymd: String) -> String {
        let parts = ymd.prefix(10).split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { return ymd }
        let months = ["January", "February", "March", "April", "May", "June", "July",
                      "August", "September", "October", "November", "December"]
        return "\(d) \(months[m - 1])"
    }
}
