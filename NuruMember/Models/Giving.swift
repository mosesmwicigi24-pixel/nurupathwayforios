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
    let createdAt: String
    let settledAt: String?
    var id: String { transactionId }

    static func == (a: GivingRecord, b: GivingRecord) -> Bool { a.transactionId == b.transactionId }
    func hash(into h: inout Hasher) { h.combine(transactionId) }
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
}

/// One balanced ledger leg behind a gift (cash + fund accounts).
struct GivingLedgerEntry: Codable, Sendable, Identifiable {
    let side: String        // debit | credit
    let account: String     // cash:stripe | fund:tithe …
    let amountMinor: Int
    let currency: String
    var id: String { "\(side)-\(account)-\(amountMinor)" }
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
    let createdAt: String
    let settledAt: String?
    let scheduleId: String?
    let ledger: [GivingLedgerEntry]
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
}
