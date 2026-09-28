// Giving Cycle 2 — money on the Give surfaces, kept pure so it can be tested:
// every amount in its own currency (a dollar gift is never shown or sent as a
// shilling number, and currencies are never added together), US-dollar entry
// for PayPal, the fee cover split out of the total, the rails' limits, and the
// church's (Nairobi) calendar year that statements count by.
import Foundation

/// One currency's total — GET /giving/statements `totals[]`, or the same shape
/// built from gift history while the server has not answered.
struct CurrencyTotal: Codable, Sendable, Hashable {
    let currency: String
    let totalMinor: Int

    init(currency: String, totalMinor: Int) {
        self.currency = currency.uppercased()
        self.totalMinor = totalMinor
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        currency = ((try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "KES").uppercased()
        totalMinor = (try? c.decodeIfPresent(Int.self, forKey: .totalMinor)) ?? 0
    }
}

enum GiveMoney {
    private static let settled: Set<String> = ["succeeded", "settled", "completed"]

    /// "KSh 1,234" (cents only when there are any: "KSh 1,234.50") ·
    /// "US$ 20.00" · "EUR 20.00". Integer minor units in, never a float.
    static func format(_ minor: Int, _ currency: String?) -> String {
        let code = (currency ?? "").uppercased()
        switch code {
        case "", "KES":
            let sign = minor < 0 ? "-" : ""
            let a = abs(minor)
            let whole = (a / 100).formatted(.number.grouping(.automatic))
            return a % 100 == 0 ? "\(sign)KSh \(whole)" : "\(sign)KSh \(whole).\(twoDigits(a % 100))"
        case "USD":
            return "US$ \(number(minor))"
        default:
            return "\(code) \(number(minor))"
        }
    }

    /// "1,234.50" — a two-decimal amount without its currency (the dollar
    /// field's big number).
    static func number(_ minor: Int) -> String {
        let sign = minor < 0 ? "-" : ""
        let a = abs(minor)
        return "\(sign)\((a / 100).formatted(.number.grouping(.automatic))).\(twoDigits(a % 100))"
    }

    /// "Kenyan shillings" · "US dollars" · "EUR" — a currency in words.
    static func currencyWords(_ currency: String) -> String {
        switch currency.uppercased() {
        case "KES": return "Kenyan shillings"
        case "USD": return "US dollars"
        case let c: return c
        }
    }

    /// Shillings first, then the rest alphabetically — the server's order.
    static func ordered(_ totals: [CurrencyTotal]) -> [CurrencyTotal] {
        totals.sorted { a, b in
            if a.currency == b.currency { return false }
            if a.currency == "KES" { return true }
            if b.currency == "KES" { return false }
            return a.currency < b.currency
        }
    }

    /// The totals as one line, shillings first: "KSh 3,500 + US$ 20.00".
    /// Never one sum across currencies. A zero total is left out; none at
    /// all reads "KSh 0".
    static func line(_ totals: [CurrencyTotal]) -> String {
        let parts = ordered(merged(totals)).filter { $0.totalMinor != 0 }
        guard !parts.isEmpty else { return format(0, "KES") }
        return parts.map { format($0.totalMinor, $0.currency) }.joined(separator: " + ")
    }

    /// The first (shillings-first) total and the line for the rest — a big
    /// number plus "+ US$ 20.00" under it. `rest` is nil with one currency.
    static func headline(_ totals: [CurrencyTotal]) -> (main: String, rest: String?) {
        let parts = ordered(merged(totals)).filter { $0.totalMinor != 0 }
        guard let first = parts.first else { return (format(0, "KES"), nil) }
        let others = parts.dropFirst()
        return (format(first.totalMinor, first.currency),
                others.isEmpty ? nil : "+ " + others.map { format($0.totalMinor, $0.currency) }.joined(separator: " + "))
    }

    /// Settled records summed per currency (shillings first).
    static func totals(of records: [GivingRecord]) -> [CurrencyTotal] {
        var sums: [String: Int] = [:]
        for r in records where settled.contains(r.status) {
            sums[r.currency.uppercased(), default: 0] += r.amountMinor
        }
        return ordered(sums.map { CurrencyTotal(currency: $0.key, totalMinor: $0.value) })
    }

    /// One row per currency (a server that repeats one is summed, never lost).
    static func merged(_ totals: [CurrencyTotal]) -> [CurrencyTotal] {
        var sums: [String: Int] = [:]
        var order: [String] = []
        for t in totals {
            if sums[t.currency] == nil { order.append(t.currency) }
            sums[t.currency, default: 0] += t.totalMinor
        }
        return order.map { CurrencyTotal(currency: $0, totalMinor: sums[$0] ?? 0) }
    }

    private static func twoDigits(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}

// MARK: - US-dollar entry (PayPal)

/// PayPal gifts are in US dollars (the server refuses any other currency,
/// 422 METHOD_CURRENCY), so while PayPal is chosen the amount is entered in
/// dollars and cents and sent as US cents.
enum UsdEntry {
    /// US$ 5 · 10 · 25 · 50 · 100, in cents.
    static let presetsCents = [500, 1000, 2500, 5000, 10000]
    /// Where the dollar field starts: US$ 10.
    static let defaultCents = 1000
    /// Whole-dollar digits the field takes — above PayPal's own US$ 10,000
    /// cap, so the cap is said by the limit line rather than a dead key.
    static let maxWholeDigits = 5

    /// The field's text after one keypad key: "0"–"9", "." or "del". At
    /// most one point and two decimals; a leading zero gives way to the
    /// next digit; "." on an empty field reads "0.".
    static func press(_ key: String, on text: String) -> String {
        switch key {
        case "del":
            return String(text.dropLast())
        case ".":
            if text.contains(".") { return text }
            return text.isEmpty ? "0." : text + "."
        default:
            guard key.count == 1, let ch = key.first, ch.isASCII, ch.isNumber else { return text }
            if let dot = text.firstIndex(of: ".") {
                return text[text.index(after: dot)...].count >= 2 ? text : text + key
            }
            if text == "0" { return key }
            return text.count >= maxWholeDigits ? text : text + key
        }
    }

    /// The field's text as cents: "12.5" → 1250, "12." → 1200, "0.05" → 5,
    /// "" or "." → 0. Anything past two decimals is ignored, never rounded up.
    static func cents(_ text: String) -> Int {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int(parts.first.map(String.init) ?? "") ?? 0
        var frac = parts.count > 1 ? String(parts[1].prefix(2)) : ""
        while frac.count < 2 { frac += "0" }
        return whole * 100 + (Int(frac) ?? 0)
    }

    /// Cents as the field's starting text: 1250 → "12.50", 1200 → "12",
    /// 5 → "0.05", 0 → "".
    static func text(_ cents: Int) -> String {
        guard cents > 0 else { return "" }
        let frac = cents % 100
        return frac == 0 ? "\(cents / 100)" : "\(cents / 100).\(frac < 10 ? "0\(frac)" : "\(frac)")"
    }
}

// MARK: - Cover the fee

/// "Cover the transaction fee" (Giving Cycle 2): the member adds the M-Pesa
/// charge so the whole gift reaches the fund. `amount_minor` on the wire stays
/// the TOTAL charged (gift + fee) — what M-Pesa collects and the books record —
/// and `cover_fee_minor` says how much of it was the fee, so the receipt can
/// say gift · fee cover · total.
enum CoverFee {
    /// Safaricom's charge in whole shillings for a gift of `giftKsh` — the
    /// table Give has always used.
    static func feeKsh(forGiftKsh a: Int) -> Int {
        switch a {
        case ...100: return 0
        case ...500: return 7
        case ...1000: return 13
        case ...1500: return 23
        case ...2500: return 33
        case ...3500: return 53
        case ...5000: return 57
        default: return Int((Double(a) * 0.012).rounded())
        }
    }

    /// What goes on the wire. The fee is covered only on a shilling rail
    /// (the table is M-Pesa's), in whole shillings, and never more than half
    /// of the total (the server refuses more); otherwise nothing is covered.
    static func split(giftMinor: Int, covering: Bool, currency: String) -> (amountMinor: Int, coverFeeMinor: Int?) {
        guard covering, giftMinor > 0, currency.uppercased() == "KES" else { return (giftMinor, nil) }
        let fee = feeKsh(forGiftKsh: giftMinor / 100) * 100
        let total = giftMinor + fee
        guard fee > 0, fee * 2 <= total else { return (giftMinor, nil) }
        return (total, fee)
    }
}

// MARK: - A rail's limits

enum GiveAmountRules {
    /// Nil when `totalMinor` can go on `rail`; otherwise what is wrong, in
    /// the server's terms (422 AMOUNT_OUT_OF_RANGE): "M-Pesa gifts are from
    /// KSh 1 to KSh 250,000." / "M-Pesa takes whole shillings — no cents."
    /// A rail with no limits sent (0 / 0) is not checked here.
    static func problem(totalMinor: Int, rail: GivingMethod) -> String? {
        let name = rail.label.isEmpty ? givingMethodName(rail.key) : rail.label
        let currency = rail.currency ?? "KES"
        if rail.maxMinor > 0, totalMinor < rail.minMinor || totalMinor > rail.maxMinor {
            return "\(name) gifts are from \(GiveMoney.format(rail.minMinor, currency)) to \(GiveMoney.format(rail.maxMinor, currency))."
        }
        if rail.wholeUnits, totalMinor % 100 != 0 {
            return "\(name) takes whole shillings — no cents."
        }
        return nil
    }
}

// MARK: - The church's calendar

/// Statements count a gift in the Nairobi year it was given (Giving Cycle 2:
/// a gift at 00:30 on 1 January belongs to the new year), so the app's own
/// sums use the same calendar as the server's `totals[]` and the PDF.
enum GiveCalendar {
    static let nairobi = TimeZone(identifier: "Africa/Nairobi") ?? TimeZone(secondsFromGMT: 3 * 3600)!

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = nairobi
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    /// This year on the church's calendar.
    static func currentYear(now: Date = Date()) -> Int { calendar.component(.year, from: now) }

    /// The Nairobi year of an ISO timestamp; the string's own year when it
    /// cannot be read as a date, nil when not even that.
    static func year(of iso: String) -> Int? {
        if let d = giveParseDate(iso) { return calendar.component(.year, from: d) }
        return Int(iso.prefix(4))
    }
}
