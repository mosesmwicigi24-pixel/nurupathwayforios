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
    /// build can carry a gift through it. `shillingsOnly` (a pledge or need
    /// payment — pledges are in shillings, and a dollar payment would be
    /// counted against a shilling promise) leaves out every other currency.
    func isSelectable(_ key: String, shillingsOnly: Bool = false) -> Bool {
        guard (method(key)?.enabled ?? false), GivingRails.appCanComplete.contains(key) else { return false }
        return !shillingsOnly || currency(key) == "KES"
    }

    /// The rails the form lists: all of them, or — paying a pledge or need —
    /// the shilling ones.
    func offered(shillingsOnly: Bool = false) -> [GivingMethod] {
        shillingsOnly ? methods.filter { currency($0.key) == "KES" } : methods
    }

    /// A weekly / monthly gift may run on it — the server's word (M-Pesa only
    /// today), and only on a rail the member can pick at all.
    func allowsRecurring(_ key: String) -> Bool {
        isSelectable(key) && (method(key)?.recurring ?? false)
    }

    /// The rail the form should have selected: the current one while it is
    /// still selectable, else the server's default, else the first selectable
    /// one — nil when none is (Give then says why instead of sending).
    func selection(keeping current: String, shillingsOnly: Bool = false) -> String? {
        if isSelectable(current, shillingsOnly: shillingsOnly) { return current }
        if let d = defaultMethod, isSelectable(d, shillingsOnly: shillingsOnly) { return d }
        return methods.first { isSelectable($0.key, shillingsOnly: shillingsOnly) }?.key
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
}
