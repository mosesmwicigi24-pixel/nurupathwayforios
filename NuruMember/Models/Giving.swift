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
    /// "Named giving" (custom sheet, optional): the member's own label for this
    /// gift (e.g. "Tithe", "Building Fund"), as entered. Null when not used.
    var accountName: String? = nil
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
        accountName = try? c.decodeIfPresent(String.self, forKey: .accountName)
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
    /// "Named giving" (custom sheet, optional): the member's own label for this
    /// gift, as entered. Null when not used.
    var accountName: String? = nil
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
        accountName = try? c.decodeIfPresent(String.self, forKey: .accountName)
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

// MARK: - Partnership

/// A member's standing as a PARTNER — someone who decided in advance to keep
/// giving, rather than someone who gave once. Derived server-side from their
/// giving schedule, so nothing here is a second copy of the truth.
///
/// Decoding is deliberately forgiving in the same way as GivingSchedule above:
/// a member should never see an error screen because one optional block was
/// absent. Absent means "nothing to say", not "something went wrong".
struct Partnership: Codable, Sendable {
    /// The schedule this standing is derived from — carried so the resume
    /// control has something real to act on.
    let scheduleId: String?
    let isPartner: Bool
    let everPartnered: Bool
    let status: String?          // active | paused (nil when not a partner)
    let since: String?
    let kept: Int                // cycles actually COLLECTED, never scheduled
    let givenMinor: Int
    let currency: String
    let rhythm: Rhythm?
    let trouble: Trouble?        // present ONLY when there is something to say
    let sinceYouBegan: Season?

    struct Rhythm: Codable, Sendable {
        let frequency: String
        let method: String
        let amountMinor: Int
        let fund: String
        let nextRunAt: String?   // nil while paused — nothing is coming
    }
    struct Trouble: Codable, Sendable {
        let paused: Bool
        let consecutiveFailures: Int
        let lastFailedAt: String?
        // No error text by design: the provider's wording is for the church's
        // admin view, not for a member who is already worried.
    }
    /// What the WHOLE CHURCH did during this partnership. Never this member's
    /// money traced to an outcome — we cannot trace a shilling to a disciple.
    struct Season: Codable, Sendable {
        let from: String
        let levelsCompleted: Int
        let modulesCompleted: Int
        let plansFinished: Int
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        scheduleId = try? c.decodeIfPresent(String.self, forKey: .scheduleId)
        isPartner = (try? c.decode(Bool.self, forKey: .isPartner)) ?? false
        everPartnered = (try? c.decode(Bool.self, forKey: .everPartnered)) ?? false
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        since = try? c.decodeIfPresent(String.self, forKey: .since)
        kept = (try? c.decode(Int.self, forKey: .kept)) ?? 0
        givenMinor = (try? c.decode(Int.self, forKey: .givenMinor)) ?? 0
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "KES"
        rhythm = try? c.decodeIfPresent(Rhythm.self, forKey: .rhythm)
        trouble = try? c.decodeIfPresent(Trouble.self, forKey: .trouble)
        sinceYouBegan = try? c.decodeIfPresent(Season.self, forKey: .sinceYouBegan)
    }
}


// MARK: - The partner invitation

/// The server's answer to "may I invite this member today, and with what".
///
/// Every rule of restraint lives on the server (invitation.ts) so the two apps
/// cannot drift apart — and they would only ever drift towards asking more
/// often. This client's whole job is: ask, render what comes back, report what
/// happened. It decides nothing.
struct PartnerInvite: Codable, Sendable {
    let show: Bool
    /// Why not, when show is false. Rendered nowhere — carried for diagnostics.
    let reason: String?
    /// Which showing this is about to be. Counted server-side so the two apps
    /// agree; used for one thing — "Don't ask again" appears from the second.
    let showing: Int?
    let campaign: Campaign?

    struct Campaign: Codable, Sendable, Identifiable {
        let campaignId: String
        let title: String
        let blurb: String
        let imageUrl: String?
        let goalMinor: Int
        let raisedMinor: Int
        let currency: String
        let endsOn: String
        let daysLeft: Int
        /// Present ONLY when a real person pledged it. Never rendered otherwise.
        let match: Match?
        let tiers: [Tier]

        /// Progress toward the goal, clamped — a campaign past its goal shows
        /// full, never a bar overflowing its track.
        var id: String { campaignId }

        var progress: Double {
            guard goalMinor > 0 else { return 0 }
            return min(1.0, Double(raisedMinor) / Double(goalMinor))
        }
    }

    struct Match: Codable, Sendable {
        let amountMinor: Int
        let pledger: String
    }

    /// An amount with its meaning. The meaning is the invitation; the amount
    /// alone is a price list.
    struct Tier: Codable, Sendable, Identifiable {
        let amountMinor: Int
        let currency: String
        let disciplesPerYear: Int
        let meaning: String
        var id: Int { amountMinor }
    }
}
