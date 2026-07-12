// Giving DTOs — Swift mirrors of the Give v2 contract in
// packages/mobile/src/api/types.ts. Money is server-authoritative + online-only
// (§5.6): the client creates a real intent/schedule and never fabricates a gift.
import Foundation

struct GivingRecord: Codable, Sendable, Identifiable, Hashable {
    let transactionId: String
    let amountMinor: Int
    let currency: String
    let status: String
    let fund: String
    let method: String?
    let providerRef: String?
    /// The M-Pesa receipt number (the 10-char code in the confirmation SMS,
    /// e.g. UG3J29U3OL). Present once a mobile-money gift settles; null for
    /// older gifts / non-mobile-money methods.
    var receiptCode: String? = nil
    let createdAt: String
    let settledAt: String?
    var id: String { transactionId }

    static func == (a: GivingRecord, b: GivingRecord) -> Bool { a.transactionId == b.transactionId }
    func hash(into h: inout Hasher) { h.combine(transactionId) }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        transactionId = try c.decode(String.self, forKey: .transactionId)
        amountMinor = (try? c.decodeIfPresent(Int.self, forKey: .amountMinor)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "KES"
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        fund = (try? c.decodeIfPresent(String.self, forKey: .fund)) ?? ""
        method = try? c.decodeIfPresent(String.self, forKey: .method)
        providerRef = try? c.decodeIfPresent(String.self, forKey: .providerRef)
        receiptCode = try? c.decodeIfPresent(String.self, forKey: .receiptCode)
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        settledAt = try? c.decodeIfPresent(String.self, forKey: .settledAt)
    }
}

/// POST /giving/intents → the created intent. The card path returns a
/// client_secret (confirmed by the Stripe SDK, cards never touch our server);
/// mobile money returns a provider ref (STK push); PayPal returns an approve_url.
struct GivingIntentResult: Codable, Sendable {
    let transactionId: String
    let status: String
    let clientSecret: String?
    let provider: String?
    let providerRef: String?
    let approveUrl: String?
    let reused: Bool
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        transactionId = (try? c.decodeIfPresent(String.self, forKey: .transactionId)) ?? ""
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        clientSecret = try? c.decodeIfPresent(String.self, forKey: .clientSecret)
        provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        providerRef = try? c.decodeIfPresent(String.self, forKey: .providerRef)
        approveUrl = try? c.decodeIfPresent(String.self, forKey: .approveUrl)
        reused = (try? c.decodeIfPresent(Bool.self, forKey: .reused)) ?? false
    }
}

/// One balanced ledger leg behind a gift (cash + fund accounts).
struct GivingLedgerEntry: Codable, Sendable, Identifiable {
    let side: String        // debit | credit
    let account: String     // cash:stripe | fund:tithe …
    let amountMinor: Int
    let currency: String
    var id: String { "\(side)-\(account)-\(amountMinor)" }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        side = (try? c.decodeIfPresent(String.self, forKey: .side)) ?? ""
        account = (try? c.decodeIfPresent(String.self, forKey: .account)) ?? ""
        amountMinor = (try? c.decodeIfPresent(Int.self, forKey: .amountMinor)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "KES"
    }
}

/// GET /giving/transactions/{id} — full detail incl. the double-entry trail.
struct GivingDetail: Codable, Sendable {
    let transactionId: String
    let amountMinor: Int
    let currency: String
    let status: String
    let fund: String
    let method: String?
    let providerRef: String?
    var receiptCode: String? = nil   // M-Pesa SMS receipt code (e.g. UG3J29U3OL)
    let createdAt: String
    let settledAt: String?
    let scheduleId: String?
    let ledger: [GivingLedgerEntry]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        transactionId = try c.decode(String.self, forKey: .transactionId)
        amountMinor = (try? c.decodeIfPresent(Int.self, forKey: .amountMinor)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "KES"
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        fund = (try? c.decodeIfPresent(String.self, forKey: .fund)) ?? ""
        method = try? c.decodeIfPresent(String.self, forKey: .method)
        providerRef = try? c.decodeIfPresent(String.self, forKey: .providerRef)
        receiptCode = try? c.decodeIfPresent(String.self, forKey: .receiptCode)
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        settledAt = try? c.decodeIfPresent(String.self, forKey: .settledAt)
        scheduleId = try? c.decodeIfPresent(String.self, forKey: .scheduleId)
        ledger = (try? c.decodeIfPresent([GivingLedgerEntry].self, forKey: .ledger)) ?? []
    }
}

struct GivingSchedule: Codable, Sendable, Identifiable {
    let scheduleId: String
    let fund: String
    let amountMinor: Int
    let currency: String
    let frequency: String   // weekly | monthly
    let method: String
    let status: String      // active | cancelled
    let nextRunAt: String
    let createdAt: String
    var id: String { scheduleId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        scheduleId = try c.decode(String.self, forKey: .scheduleId)
        fund = (try? c.decodeIfPresent(String.self, forKey: .fund)) ?? ""
        amountMinor = (try? c.decodeIfPresent(Int.self, forKey: .amountMinor)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "KES"
        frequency = (try? c.decodeIfPresent(String.self, forKey: .frequency)) ?? "monthly"
        method = (try? c.decodeIfPresent(String.self, forKey: .method)) ?? ""
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "active"
        nextRunAt = (try? c.decodeIfPresent(String.self, forKey: .nextRunAt)) ?? ""
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
    }
}
