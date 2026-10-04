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

    /// "0711 222 333" — how a Kenyan reads their own number (Android's
    /// kenyanMobileDisplay); anything that is not one comes back as given.
    /// For the screen only — the wire always carries E.164.
    static func display(_ raw: String) -> String {
        guard let e164 = normalize(raw) else { return raw }
        let local = Array("0" + e164.dropFirst(4))   // "+254" → "0"
        return "\(String(local[0..<4])) \(String(local[4..<7])) \(String(local[7...]))"
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

    /// The rails a gift can go through here, by name — the server says they
    /// take money AND this build can carry a gift through them (`isSelectable`).
    func selectableNames() -> [String] {
        methods.filter { isSelectable($0.key) }
            .map { $0.label.isEmpty ? givingMethodName($0.key) : $0.label }
    }

    /// Home's giving card line (EXPERIENCE.md §2, promise only what works):
    /// "Tithe & offering · M-Pesa" — only the rails that work here; just
    /// "Tithe & offering" until the methods have loaded, or when none does.
    static func homeGiveLine(_ methods: GivingMethods?) -> String {
        let names = methods?.selectableNames() ?? []
        return names.isEmpty ? "Tithe & offering" : "Tithe & offering · " + names.joined(separator: ", ")
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

// MARK: - RECURRING GIFTS

enum GiveSchedules {
    /// What Give lists under RECURRING GIFTS: running schedules, then paused
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
    /// Anything else, in the one state language (EXPERIENCE.md §4, §7.3): a
    /// refusal in our own words keeps them — the 422 METHOD_UNAVAILABLE /
    /// METHOD_CURRENCY / AMOUNT_OUT_OF_RANGE / PHONE_REQUIRED and 409
    /// SCHEDULE_EXISTS among them; Giving Cycle 6's 429 RATE_LIMITED (several
    /// prompts to a number not the member's own; its words name the minutes)
    /// and 409 CONFLICT (a request key another gift holds), neither ever sent
    /// again by itself. A 5xx, a dropped or unreadable answer, the generic
    /// body-parse refusal — never the server's raw text ("Internal server
    /// error" reached Give's failed screen) — read as §4 says: "Something
    /// went wrong on our side. It isn't you — please try again in a moment.",
    /// or "You're offline…" only when the phone has no network.
    case message(String)

    static func from(_ error: Error, deviceOnline: Bool? = SyncCoordinator.devicePathOnline) -> GiveRefusal {
        if case let .http(_, code, message, details)? = error as? APIError, code == "GIFT_IN_PROGRESS",
           let tx = details?.transactionId {
            return .promptWaiting(transactionId: tx, message: message)
        }
        return .message(NuruStateCopy.failure(error, deviceOnline: deviceOnline).sentence)
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

    /// 409 CONFLICT "That request key is already in use" (Giving Cycle 6):
    /// the key belongs to another gift and nothing was made or rung. The
    /// request itself was fine — with a fresh key the member's next tap goes
    /// through. (Never sent again by itself: a key is spent by any answer.)
    static func isKeyConflict(_ error: Error) -> Bool {
        if case let .http(status, code, _, _)? = error as? APIError { return status == 409 && code == "CONFLICT" }
        return false
    }
}

// MARK: - Request keys (Giving Cycle 6)

/// The idempotency key a gift, a retry, a schedule or a pledge carries. The
/// server keeps some shapes for itself — `sched:`, `claim:`, `pledge:`,
/// `web:`, `website:`, `office:` (a member's key shaped like a schedule
/// cycle's could make the scheduler skip that cycle) — and answers 400 to
/// one; a key another gift holds is 409 CONFLICT. The app's keys are random
/// UUIDs: never in those namespaces (a UUID has no colon), within the
/// server's 8–255 characters, and never used again once any answer came.
enum GiveKey {
    /// The server's own namespaces (FinancialService.RESERVED_KEY), matched
    /// without regard to case, as the server matches them.
    static let reservedPrefixes = ["sched:", "claim:", "pledge:", "web:", "website:", "office:"]

    /// A new key — the only way the app makes one for giving.
    static func fresh() -> String { UUID().uuidString }

    /// `key` is in one of the server's namespaces.
    static func isReserved(_ key: String) -> Bool {
        let k = key.lowercased()
        return reservedPrefixes.contains { k.hasPrefix($0) }
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
    /// the same one while the server never answered, or when only the KEY
    /// was refused (409 CONFLICT — the next tap sends a fresh one, Giving
    /// Cycle 6); none after the server refused the gift itself (the same
    /// request would be refused again, a 429 RATE_LIMITED included) — then
    /// it is the form's turn. Never retried without a tap.
    static func target(after error: Error, retrying transactionId: String) -> String? {
        GiveRefusal.gotNoServerAnswer(error) || GiveRefusal.isKeyConflict(error) ? transactionId : nil
    }

    /// The idempotency key the next retry sends: the same one only when the
    /// last attempt got no server answer (so a retry that did land is found,
    /// not doubled); a fresh one after any answer, and after success (`nil`).
    static func key(after error: Error?, current: String, fresh: () -> String = GiveKey.fresh) -> String {
        if let error, GiveRefusal.gotNoServerAnswer(error) { return current }
        return fresh()
    }
}

// MARK: - The M-Pesa wait (EXPERIENCE.md §7.2 #5)

/// How "Check your phone" watches a gift while it is on screen. It used to
/// give up after 20 looks 3 s apart: a prompt answered at 70 s never landed,
/// and with no button the member had to quit the app. Now: every 3 s for the
/// first minute (most prompts are answered in seconds), then every 10 s up to
/// five minutes, so a late answer still lands. Past the minute the line says
/// it is still processing and "Done" becomes the primary; a quiet "Close"
/// is there from the start. Closing never cancels or changes the gift —
/// Give's reload shows how it ended. Pure; Android uses the same line.
enum StkWatch {
    /// When the wait turns late: the line changes, Done leads.
    static let lateAfter: TimeInterval = 60
    /// How long the stage keeps looking while it is on screen.
    static let watchFor: TimeInterval = 300
    static let lateLine = "Still processing — it will show in Recent giving once it clears."

    /// Seconds before the next look, `elapsed` seconds into the wait — nil
    /// once the watch is over.
    static func nextDelay(elapsed: TimeInterval) -> TimeInterval? {
        guard elapsed < watchFor else { return nil }
        return elapsed < lateAfter ? 3 : 10
    }

    /// Past the minute: the late line, and Done as the primary.
    static func isLate(elapsed: TimeInterval) -> Bool { elapsed >= lateAfter }
}

// MARK: - The last tap before money moves (EXPERIENCE.md §7.2 #6)

enum GiveButton {
    /// The M-Pesa / Airtel number sheet's button names the money it sends
    /// (§7.1 rule 7): "Give KSh 1,000" — the form's total, in its own
    /// currency, exactly what the intent carries. A recurring start keeps
    /// "Start Monthly Gift" / "Start Weekly Gift" (it names its money on the
    /// line above). "Give Now" only if the amount is somehow unknown.
    static func mobileMoneyLabel(amountLabel: String, frequency: String?) -> String {
        if let frequency {
            return "Start \(ScheduleRhythm.isWeekly(frequency) ? "Weekly" : "Monthly") Gift"
        }
        let amount = amountLabel.trimmingCharacters(in: .whitespaces)
        return amount.isEmpty ? "Give Now" : "Give \(amount)"
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
        // …and the office's change to it at the member's request (Cycle 7) —
        // a cancelled one is not listed, so that tap lands on Give itself.
        if ["giving_schedule_failed", "giving_schedule_paused", "giving_schedule_office_change"].contains(template),
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
        // Giving Cycle 7 — the office changed it at the member's request.
        case "giving_schedule_office_change":
            switch payload?.action {
            case "cancel": return "Your recurring gift was cancelled"
            case "resume": return "Your recurring gift is back on"
            default: return "Your recurring gift is paused"
            }
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
        // A department need — a giving target (PARTNERS_PROGRAMME §4). Its
        // payload `title` is the NEED's name, so these words come first.
        case "department_need_open": return "\(nonEmpty(payload?.title) ?? "A need") — giving is open"
        case "department_need_approved": return "Your need was approved"
        case "department_need_rejected": return "About the need you submitted"
        case "department_need_closed": return "Need closed"
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
        case "department_need_open":
            return "Your department has a need you can help carry. Open Departments to give."
        case "department_need_approved":
            return "\(nonEmpty(payload?.title) ?? "The need") is open for giving."
        case "department_need_rejected":
            return nonEmpty(payload?.note) ?? "\(nonEmpty(payload?.title) ?? "The need") was not approved this time."
        case "department_need_closed":
            return "\(nonEmpty(payload?.title) ?? "The need") has been closed. Thank you."
        case "giving_schedule_office_change":
            let gift = "\(payload?.frequency?.lowercased() == "weekly" ? "weekly" : "monthly") gift of \(amount)"
                + (nonEmpty(payload?.fundName).map { " to \($0)" } ?? "")
            switch payload?.action {
            case "cancel": return "The church office cancelled your \(gift), as you asked. Nothing more will be prompted."
            case "resume": return "The church office resumed your \(gift), as you asked."
            default:
                let until = nonEmpty(payload?.resumeOn).map { " — it starts again on \(dayWords($0))" } ?? ""
                return "The church office paused your \(gift), as you asked\(until)."
            }
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
