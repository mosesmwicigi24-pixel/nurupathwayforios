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
    /// The pledge this gift counted toward (Partners statement, 2026-09-25):
    /// `pledge_id` + the pledge's name as the server says it. Both absent on
    /// older servers and on gifts given outside a pledge — the statement row
    /// then carries no pledge tag.
    var pledgeId: String? = nil
    var pledgeTitle: String? = nil
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
        pledgeId = (try? c.decodeIfPresent(String.self, forKey: .pledgeId)).flatMap { $0.isEmpty ? nil : $0 }
        pledgeTitle = (try? c.decodeIfPresent(String.self, forKey: .pledgeTitle)).flatMap { $0.isEmpty ? nil : $0 }
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
    /// Where the SERVER routed the gift (pledge names contract): the fund it
    /// landed in — for a pledge payment that is the pledge's own target, not
    /// the chip the member had selected — and the pledge it counts toward,
    /// when it carried a `pledge_id`. Both absent on older servers.
    let fund: Pledge.FundRef?
    let pledge: PledgeRef?

    struct PledgeRef: Codable, Sendable {
        let pledgeId: String
        let title: String
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            pledgeId = (try? c.decodeIfPresent(String.self, forKey: .pledgeId)) ?? ""
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        }
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        transactionId = (try? c.decodeIfPresent(String.self, forKey: .transactionId)) ?? ""
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        clientSecret = try? c.decodeIfPresent(String.self, forKey: .clientSecret)
        provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        providerRef = try? c.decodeIfPresent(String.self, forKey: .providerRef)
        approveUrl = try? c.decodeIfPresent(String.self, forKey: .approveUrl)
        reused = (try? c.decodeIfPresent(Bool.self, forKey: .reused)) ?? false
        fund = try? c.decodeIfPresent(Pledge.FundRef.self, forKey: .fund)
        pledge = try? c.decodeIfPresent(PledgeRef.self, forKey: .pledge)
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
    // Receipt v2 (2026-09-25) — display fields the server adds to the same
    // payload. All optional: an older server omits them and the receipt falls
    // back to the fund code / the local method map / the signed-in profile.
    /// The fund's display name ("Discipleship"), not its code.
    var fundName: String? = nil
    /// The pledge this gift counts toward, when it carried a `pledge_id`.
    var pledge: GivingIntentResult.PledgeRef? = nil
    /// The department need this gift was given to, when it targeted one.
    var need: NeedRef? = nil
    /// "M-Pesa" | "Airtel Money" | "Card" | "PayPal" | "Manual".
    var methodLabel: String? = nil
    /// The giver's full name as Finance holds it.
    var memberName: String? = nil
    /// The giver's congregation, when known.
    var congregation: String? = nil

    struct NeedRef: Codable, Sendable {
        let needId: String
        let title: String
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            needId = (try? c.decodeIfPresent(String.self, forKey: .needId)) ?? ""
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        }
    }

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
        fundName = try? c.decodeIfPresent(String.self, forKey: .fundName)
        pledge = try? c.decodeIfPresent(GivingIntentResult.PledgeRef.self, forKey: .pledge)
        need = try? c.decodeIfPresent(NeedRef.self, forKey: .need)
        methodLabel = try? c.decodeIfPresent(String.self, forKey: .methodLabel)
        memberName = try? c.decodeIfPresent(String.self, forKey: .memberName)
        congregation = try? c.decodeIfPresent(String.self, forKey: .congregation)
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

    // Partners programme (PARTNERS_PROGRAMME §5, GET /giving/partnership):
    // the membership record, the derived tier, every pledge with its
    // computed progress, and the merged due list. All tolerant — a server
    // that predates the programme still renders the standing above.
    let membership: Membership?
    let tier: Tier?
    let pledges: [Pledge]
    let due: [DueItem]
    /// Campaigns a new pledge may target (chips in the "target" step). Empty
    /// when the server sends none — the step then offers funds only.
    let campaigns: [PledgeCampaignOption]
    /// What a new pledge may be for (pledge names contract): General
    /// partnership first, then funds, campaigns, approved department needs —
    /// in the server's order. Empty on servers that predate it; the flow
    /// then builds the same list from the five funds + `campaigns`.
    let pledgeOptions: [PledgeOption]

    /// A partner per §1: the membership says so, or (pre-programme servers)
    /// the derived standing does.
    var isProgrammeMember: Bool {
        if let m = membership { return m.status == "active" || m.status == "paused" }
        return isPartner
    }

    struct Membership: Codable, Sendable {
        let status: String       // active | paused | left
        let joinedAt: String?
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
            joinedAt = try? c.decodeIfPresent(String.self, forKey: .joinedAt)
        }
    }
    /// Derived server-side from the monthly commitment vs giving-tier
    /// economics — never computed here.
    struct Tier: Codable, Sendable {
        let name: String
        let monthlyMinor: Int
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            monthlyMinor = (try? c.decodeIfPresent(Int.self, forKey: .monthlyMinor)) ?? 0
        }
    }

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
        membership = try? c.decodeIfPresent(Membership.self, forKey: .membership)
        tier = try? c.decodeIfPresent(Tier.self, forKey: .tier)
        pledges = (try? c.decodeIfPresent([Pledge].self, forKey: .pledges)) ?? []
        due = (try? c.decodeIfPresent([DueItem].self, forKey: .due)) ?? []
        campaigns = (try? c.decodeIfPresent([PledgeCampaignOption].self, forKey: .campaigns)) ?? []
        pledgeOptions = (try? c.decodeIfPresent([PledgeOption].self, forKey: .pledgeOptions)) ?? []
    }
}

// MARK: - Pledges (PARTNERS_PROGRAMME §1, §5)

/// A promise: `monthly` (amount_minor each month, open-ended) or `total`
/// (target_minor by due_on, paid in any instalments). Progress is COMPUTED
/// by the server and never stored — this struct carries it, never derives it.
struct Pledge: Codable, Sendable, Identifiable, Hashable {
    let pledgeId: String
    let shape: String            // monthly | total
    let amountMinor: Int?        // monthly
    let targetMinor: Int?        // total
    let currency: String
    let dueDay: Int?             // monthly: 1–28
    let dueOn: String?           // total: yyyy-MM-dd
    let fund: FundRef?
    let campaign: CampaignRef?
    let needId: String?
    /// The pledge's name as the SERVER says it (pledge names contract): the
    /// member's custom name when set, else the derived one (campaign → fund
    /// → need → "General partnership"). Empty on servers that predate it.
    let title: String
    /// The member's own name for the pledge; nil when they never gave one
    /// (or cleared it) and `title` is the derived name.
    let customTitle: String?
    let status: String           // active | paused | fulfilled | cancelled
    let progress: Progress
    let scheduleId: String?
    let remindersEnabled: Bool
    let createdAt: String?
    /// The fund this pledge's money goes to (`pays_to {code, name}`) — the
    /// server's one rule (pledge → campaign → need's department → programme
    /// default), so what a pledge says it pays to is where its money goes.
    /// Nil on older servers: Give then says "Routed by the church".
    let paysTo: FundRef?
    var id: String { pledgeId }

    struct FundRef: Codable, Sendable, Hashable {
        let code: String
        let name: String
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        }
    }
    struct CampaignRef: Codable, Sendable, Hashable {
        let campaignId: String
        let title: String
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            campaignId = (try? c.decodeIfPresent(String.self, forKey: .campaignId)) ?? ""
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        }
    }
    struct Progress: Codable, Sendable, Hashable {
        let paidMinor: Int           // total: sum paid; monthly: all-time paid
        let periodPaidMinor: Int?    // monthly: paid in the current period
        let label: String            // on_track | behind | fulfilled | paused
        let nextDue: String?         // yyyy-MM-dd or ISO timestamp
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            paidMinor = (try? c.decodeIfPresent(Int.self, forKey: .paidMinor)) ?? 0
            periodPaidMinor = try? c.decodeIfPresent(Int.self, forKey: .periodPaidMinor)
            label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? "on_track"
            nextDue = try? c.decodeIfPresent(String.self, forKey: .nextDue)
        }
        init(paidMinor: Int = 0, periodPaidMinor: Int? = nil, label: String = "on_track", nextDue: String? = nil) {
            self.paidMinor = paidMinor; self.periodPaidMinor = periodPaidMinor
            self.label = label; self.nextDue = nextDue
        }
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        pledgeId = (try? c.decodeIfPresent(String.self, forKey: .pledgeId)) ?? ""
        shape = (try? c.decodeIfPresent(String.self, forKey: .shape)) ?? "monthly"
        amountMinor = try? c.decodeIfPresent(Int.self, forKey: .amountMinor)
        targetMinor = try? c.decodeIfPresent(Int.self, forKey: .targetMinor)
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "KES"
        dueDay = try? c.decodeIfPresent(Int.self, forKey: .dueDay)
        dueOn = try? c.decodeIfPresent(String.self, forKey: .dueOn)
        fund = try? c.decodeIfPresent(FundRef.self, forKey: .fund)
        campaign = try? c.decodeIfPresent(CampaignRef.self, forKey: .campaign)
        needId = try? c.decodeIfPresent(String.self, forKey: .needId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        customTitle = (try? c.decodeIfPresent(String.self, forKey: .customTitle)).flatMap { $0.isEmpty ? nil : $0 }
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "active"
        progress = (try? c.decodeIfPresent(Progress.self, forKey: .progress)) ?? Progress()
        scheduleId = try? c.decodeIfPresent(String.self, forKey: .scheduleId)
        remindersEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .remindersEnabled)) ?? true
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        paysTo = (try? c.decodeIfPresent(FundRef.self, forKey: .paysTo)).flatMap { $0.code.isEmpty && $0.name.isEmpty ? nil : $0 }
    }

    static func == (a: Pledge, b: Pledge) -> Bool { a.pledgeId == b.pledgeId && a.status == b.status && a.progress == b.progress && a.remindersEnabled == b.remindersEnabled && a.amountMinor == b.amountMinor && a.dueDay == b.dueDay && a.title == b.title && a.customTitle == b.customTitle }
    func hash(into h: inout Hasher) { h.combine(pledgeId) }

    var isMonthly: Bool { shape == "monthly" }
    /// The promise itself in minor units — the monthly amount or the total target.
    var commitmentMinor: Int { isMonthly ? (amountMinor ?? 0) : (targetMinor ?? 0) }
    /// Paid against the current promise: this period for monthly, all-time for total.
    var paidTowardMinor: Int { isMonthly ? (progress.periodPaidMinor ?? 0) : progress.paidMinor }
    /// Still owed this period / toward the target — what "Pay now" pre-fills.
    var remainingMinor: Int { max(0, commitmentMinor - paidTowardMinor) }
    /// 0…1, clamped — a fulfilled pledge shows full, never a bar past its track.
    var fraction: Double {
        guard commitmentMinor > 0 else { return 0 }
        return min(1, Double(paidTowardMinor) / Double(commitmentMinor))
    }
    /// What the pledge is for, derived HERE from its target: fund, campaign,
    /// need, or general. The fallback behind `displayTitle` for servers that
    /// send no `title`.
    var targetTitle: String {
        if let c = campaign, !c.title.isEmpty { return c.title }
        if let f = fund, !f.name.isEmpty { return f.name }
        if let f = fund, !f.code.isEmpty { return f.code.capitalized }
        if needId != nil { return "A department need" }
        return "General partnership"
    }
    /// The name shown everywhere a pledge is named: the server's `title`
    /// (custom, else derived), falling back to `targetTitle` when absent.
    var displayTitle: String { title.isEmpty ? targetTitle : title }
}

/// One thing a new pledge may be for (GET /giving/partnership
/// `pledge_options[]`): General partnership, a fund, a campaign, or an
/// approved department need. Picking one sets the create body's
/// `fund` / `campaign_id` / `need_id`; the server derives the title.
struct PledgeOption: Codable, Sendable, Identifiable, Hashable {
    let key: String
    let title: String
    let kind: String             // general | fund | campaign | need
    let fund: String?            // kind == fund: the fund code
    let campaignId: String?      // kind == campaign
    let needId: String?          // kind == need
    /// The server's key, or (a row without one) a stable composite so the
    /// picker can still tell two options apart.
    var id: String { key.isEmpty ? "\(kind):\(fund ?? campaignId ?? needId ?? title)" : key }

    init(key: String, title: String, kind: String, fund: String? = nil, campaignId: String? = nil, needId: String? = nil) {
        self.key = key; self.title = title; self.kind = kind
        self.fund = fund; self.campaignId = campaignId; self.needId = needId
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        key = (try? c.decodeIfPresent(String.self, forKey: .key)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "general"
        fund = try? c.decodeIfPresent(String.self, forKey: .fund)
        campaignId = try? c.decodeIfPresent(String.self, forKey: .campaignId)
        needId = try? c.decodeIfPresent(String.self, forKey: .needId)
    }
}

/// One row of the merged due list (§2.3): a pledge instalment or a schedule
/// run, soonest first, with the one action that clears it.
struct DueItem: Codable, Sendable, Identifiable, Hashable {
    let kind: String             // pledge | schedule
    let id: String
    let title: String
    let amountMinor: Int
    let currency: String
    let dueOn: String
    let action: String           // pay | resume
    /// A pledge instalment's fund (`pays_to`), as on the pledge. Nil when absent.
    let paysTo: Pledge.FundRef?
    /// Money toward this instalment the server has STARTED but not settled
    /// (a 15-minute window). 0 when absent. At or above `amountMinor` the row
    /// shows Processing instead of Pay; below it, Pay covers the remainder.
    let pendingMinor: Int
    /// What is still uncovered once the in-flight money lands.
    var uncoveredMinor: Int { max(0, amountMinor - pendingMinor) }
    /// Every shilling of this pledge instalment is already on its way.
    var fullyPending: Bool { kind == "pledge" && action != "resume" && pendingMinor > 0 && pendingMinor >= amountMinor }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "pledge"
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        amountMinor = (try? c.decodeIfPresent(Int.self, forKey: .amountMinor)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "KES"
        dueOn = (try? c.decodeIfPresent(String.self, forKey: .dueOn)) ?? ""
        action = (try? c.decodeIfPresent(String.self, forKey: .action)) ?? "pay"
        paysTo = (try? c.decodeIfPresent(Pledge.FundRef.self, forKey: .paysTo)).flatMap { $0.code.isEmpty && $0.name.isEmpty ? nil : $0 }
        pendingMinor = max(0, c.flexInt(.pendingMinor) ?? 0)
    }
}

/// A campaign a pledge may target — offered as a chip in the new-pledge flow
/// when the partnership payload carries any.
struct PledgeCampaignOption: Codable, Sendable, Identifiable, Hashable {
    let campaignId: String
    let title: String
    var id: String { campaignId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        campaignId = (try? c.decodeIfPresent(String.self, forKey: .campaignId)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
    }
}

/// A `transactions` row attributed to a pledge (§1 "Pledge payment"). Also
/// the row shape of GET /giving/statements `payments[]`; `at` falls back to
/// the transaction's settled/created timestamp so either serialisation lands.
struct PledgePayment: Decodable, Sendable, Identifiable, Hashable {
    let transactionId: String
    let amountMinor: Int
    let currency: String
    let at: String
    let receiptCode: String?
    let pledgeId: String?
    let fund: String?
    let status: String?
    // Partners statement (2026-09-25) — the row's own display fields. All
    // optional: an older server omits them and the row falls back to the
    // statement's byPledge title / the fund code / no method.
    /// The pledge's name as the server says it.
    var pledgeTitle: String? = nil
    /// The fund's display name ("Discipleship"), not its code.
    var fundName: String? = nil
    /// The rail the gift came in on (mpesa | airtel | card | paypal …).
    var method: String? = nil
    var id: String { transactionId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        transactionId = (try? c.decodeIfPresent(String.self, forKey: .transactionId)) ?? ""
        amountMinor = (try? c.decodeIfPresent(Int.self, forKey: .amountMinor)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "KES"
        at = (try? c.decodeIfPresent(String.self, forKey: .at))
            ?? (try? c.decodeIfPresent(String.self, forKey: .settledAt))
            ?? (try? c.decodeIfPresent(String.self, forKey: .createdAt))
            ?? ""
        receiptCode = try? c.decodeIfPresent(String.self, forKey: .receiptCode)
        pledgeId = try? c.decodeIfPresent(String.self, forKey: .pledgeId)
        fund = try? c.decodeIfPresent(String.self, forKey: .fund)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        pledgeTitle = (try? c.decodeIfPresent(String.self, forKey: .pledgeTitle)).flatMap { $0.isEmpty ? nil : $0 }
        fundName = (try? c.decodeIfPresent(String.self, forKey: .fundName)).flatMap { $0.isEmpty ? nil : $0 }
        method = (try? c.decodeIfPresent(String.self, forKey: .method)).flatMap { $0.isEmpty ? nil : $0 }
    }
    enum CodingKeys: String, CodingKey {
        case transactionId, amountMinor, currency, at, settledAt, createdAt, receiptCode, pledgeId, fund, status
        case pledgeTitle, fundName, method
    }
}

/// GET /giving/pledges/{id} → the pledge + its payments (+ reminders, which
/// this phase reads but does not render). Accepts both `{pledge: {…},
/// payments}` and a flat pledge with `payments` beside it.
struct PledgeDetail: Decodable, Sendable {
    let pledge: Pledge
    let payments: [PledgePayment]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let nested = try? c.decodeIfPresent(Pledge.self, forKey: .pledge), !nested.pledgeId.isEmpty {
            pledge = nested
        } else {
            pledge = try Pledge(from: d)
        }
        payments = (try? c.decodeIfPresent([PledgePayment].self, forKey: .payments)) ?? []
    }
    enum CodingKeys: String, CodingKey { case pledge, payments }
}

/// POST /giving/partners/join → the membership (flat, or wrapped as
/// `{membership: {…}}`).
struct PartnerJoinResult: Decodable, Sendable {
    let membership: Partnership.Membership
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let nested = try? c.decodeIfPresent(Partnership.Membership.self, forKey: .membership), !nested.status.isEmpty {
            membership = nested
        } else {
            membership = try Partnership.Membership(from: d)
        }
    }
    enum CodingKeys: String, CodingKey { case membership }
}

/// POST /giving/pledges (and PATCH) → the pledge, flat or `{pledge: {…}}`.
struct PledgeResult: Decodable, Sendable {
    let pledge: Pledge
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let nested = try? c.decodeIfPresent(Pledge.self, forKey: .pledge), !nested.pledgeId.isEmpty {
            pledge = nested
        } else {
            pledge = try Pledge(from: d)
        }
    }
    enum CodingKeys: String, CodingKey { case pledge }
}

/// GET /giving/statements?year= — the JSON statement (§5): totals by pledge
/// and by fund for one year, the payments behind them, and the years that
/// have any. The yearly PDF stays on GivingStatementView.
struct GivingStatements: Decodable, Sendable {
    let years: [Int]
    let year: Int
    let totalMinor: Int
    let currency: String
    let byPledge: [ByPledge]
    let byFund: [ByFund]
    let payments: [PledgePayment]
    // Partners statement (2026-09-25, additive): the server's own three
    // numbers for the year and one entry per pledge that lived in it. All
    // optional — an older server sends none and PartnersStatementView
    // computes the same numbers locally from the pledges (PledgeMath).
    /// Σ over the year's pledges of what was promised in that year.
    var pledgedMinor: Int? = nil
    /// Σ payments carrying a pledge id in that year.
    var paidMinor: Int? = nil
    /// max(pledged − paid, 0).
    var remainingMinor: Int? = nil
    /// One row per pledge in the year (`pledges[]`); empty when absent.
    var pledges: [StatementPledge] = []

    // Statement v2 (2026-09-25, additive — PARTNERS_PROGRAMME §3d): the
    // impact-led Partners statement. Every block is optional and every field
    // inside it is tolerant — an older server sends none of them and the
    // page hides the block rather than showing a number it was never sent.
    /// What the year's pledge money amounts to in the tier costing.
    var impact: Impact? = nil
    /// Jan→Dec, one status each. Nil when absent or empty.
    var months: [MonthStatus]? = nil
    /// The year's monthly-commitment counts.
    var faithfulness: Faithfulness? = nil
    /// The church-wide "since you began" line; nil when absent or null.
    var season: Season? = nil
    /// Pledge payments the server has not settled yet (`pending[]`) — shown
    /// as "Processing" rows, NEVER counted in any total. Empty when absent.
    var pending: [PledgePayment] = []

    /// `impact` — paid toward pledges, and what that carries at KSh 20,000
    /// per disciple per level (`disciples_carried` = floor(paid ÷ per
    /// disciple); `toward_next_minor` = what is paid toward the next one).
    struct Impact: Decodable, Sendable {
        let paidMinor: Int?
        let perDiscipleMinor: Int?
        let disciplesCarried: Int?
        let towardNextMinor: Int?

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            paidMinor = c.flexInt(.paidMinor)
            perDiscipleMinor = c.flexInt(.perDiscipleMinor)
            disciplesCarried = c.flexInt(.disciplesCarried)
            // The brief names it `toward_next_minor`, the programme doc
            // `toward_next` — read either.
            towardNextMinor = c.flexInt(.towardNextMinor) ?? c.flexInt(.towardNext)
        }
        enum CodingKeys: String, CodingKey {
            case paidMinor, perDiscipleMinor, disciplesCarried, towardNextMinor, towardNext
        }
    }

    /// One month of the faithfulness strip.
    struct MonthStatus: Decodable, Sendable, Hashable {
        /// 1…12 when the server's `month` is readable (3, "3", "2026-03" or
        /// "2026-03-01"); nil otherwise — the strip then uses the position.
        let month: Int?
        /// kept | late | missed | upcoming | none (lower-cased; "none" when absent).
        let status: String
        let dueMinor: Int?
        let paidMinor: Int?

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            if let n = c.flexInt(.month), (1...12).contains(n) {
                month = n
            } else if let s = try? c.decodeIfPresent(String.self, forKey: .month) {
                let parts = s.split(separator: "-")
                month = parts.count >= 2 ? Int(parts[1]).flatMap { (1...12).contains($0) ? $0 : nil } : nil
            } else {
                month = nil
            }
            status = (try? c.decodeIfPresent(String.self, forKey: .status))?.lowercased() ?? "none"
            dueMinor = c.flexInt(.dueMinor)
            paidMinor = c.flexInt(.paidMinor)
        }
        enum CodingKeys: String, CodingKey { case month, status, dueMinor, paidMinor }
    }

    /// `faithfulness` — kept on time, late, missed, and how many fell due.
    struct Faithfulness: Decodable, Sendable {
        let keptOnTime: Int?
        let late: Int?
        let missed: Int?
        let dueCount: Int?

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            keptOnTime = c.flexInt(.keptOnTime)
            late = c.flexInt(.late)
            missed = c.flexInt(.missed)
            dueCount = c.flexInt(.dueCount)
        }
        enum CodingKeys: String, CodingKey { case keptOnTime, late, missed, dueCount }
    }

    /// `season` — what the WHOLE CHURCH did while this member partnered.
    /// Never this member's money traced to an outcome.
    struct Season: Decodable, Sendable {
        let from: String?
        let levelsCompleted: Int?
        let modulesCompleted: Int?
        let plansFinished: Int?

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            from = try? c.decodeIfPresent(String.self, forKey: .from)
            levelsCompleted = c.flexInt(.levelsCompleted)
            modulesCompleted = c.flexInt(.modulesCompleted)
            plansFinished = c.flexInt(.plansFinished)
        }
        enum CodingKeys: String, CodingKey { case from, levelsCompleted, modulesCompleted, plansFinished }
    }

    /// One pledge as the yearly statement reports it — the promise, its
    /// status, and the year's pledged / paid / kept figures, computed by the
    /// server. `kept` is cycles COLLECTED; `dueCount` is cycles that have
    /// fallen due so far in the year.
    struct StatementPledge: Decodable, Sendable, Identifiable, Hashable {
        let pledgeId: String
        let title: String
        let shape: String            // monthly | total
        let amountMinor: Int?        // monthly
        let targetMinor: Int?        // total
        let currency: String
        let status: String           // active | paused | fulfilled | cancelled
        let dueDay: Int?             // monthly: 1–28
        let dueOn: String?           // total: yyyy-MM-dd
        let createdAt: String?
        let pledgedMinor: Int
        let paidMinor: Int
        let kept: Int
        let dueCount: Int
        /// Statement v2: what is still owed on this pledge in the year. Nil
        /// on older servers (and on the local-math rows).
        var remainingYearMinor: Int? = nil
        /// Statement v2, department-need pledges only: how far the WHOLE
        /// church has got toward the need, as sent (may be fractional). Nil
        /// when absent or null; the row shows it floored and held to 0…100.
        var churchProgressPercent: Double? = nil
        var id: String { pledgeId }
        var isMonthly: Bool { shape == "monthly" }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            pledgeId = (try? c.decodeIfPresent(String.self, forKey: .pledgeId)) ?? ""
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            shape = (try? c.decodeIfPresent(String.self, forKey: .shape)) ?? "monthly"
            amountMinor = try? c.decodeIfPresent(Int.self, forKey: .amountMinor)
            targetMinor = try? c.decodeIfPresent(Int.self, forKey: .targetMinor)
            currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "KES"
            status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "active"
            dueDay = try? c.decodeIfPresent(Int.self, forKey: .dueDay)
            dueOn = try? c.decodeIfPresent(String.self, forKey: .dueOn)
            createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
            pledgedMinor = (try? c.decodeIfPresent(Int.self, forKey: .pledgedMinor)) ?? 0
            paidMinor = (try? c.decodeIfPresent(Int.self, forKey: .paidMinor)) ?? 0
            kept = (try? c.decodeIfPresent(Int.self, forKey: .kept)) ?? 0
            dueCount = (try? c.decodeIfPresent(Int.self, forKey: .dueCount)) ?? 0
            remainingYearMinor = c.flexInt(.remainingYearMinor).map { max(0, $0) }
            churchProgressPercent = c.flexDouble(.churchProgressPercent)
        }

        /// The local-math twin: built from a `Pledge` when the server sends
        /// no `pledges[]` (PartnersStatementView's fallback).
        init(pledgeId: String, title: String, shape: String, amountMinor: Int?, targetMinor: Int?,
             currency: String, status: String, dueDay: Int?, dueOn: String?, createdAt: String?,
             pledgedMinor: Int, paidMinor: Int, kept: Int, dueCount: Int) {
            self.pledgeId = pledgeId; self.title = title; self.shape = shape
            self.amountMinor = amountMinor; self.targetMinor = targetMinor
            self.currency = currency; self.status = status
            self.dueDay = dueDay; self.dueOn = dueOn; self.createdAt = createdAt
            self.pledgedMinor = pledgedMinor; self.paidMinor = paidMinor
            self.kept = kept; self.dueCount = dueCount
        }

        enum CodingKeys: String, CodingKey {
            case pledgeId, title, shape, amountMinor, targetMinor, currency, status, dueDay, dueOn, createdAt
            case pledgedMinor, paidMinor, kept, dueCount
            case remainingYearMinor, churchProgressPercent
        }
    }

    struct ByPledge: Codable, Sendable, Identifiable {
        let pledgeId: String
        let title: String
        let totalMinor: Int
        var id: String { pledgeId }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            pledgeId = (try? c.decodeIfPresent(String.self, forKey: .pledgeId)) ?? ""
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            totalMinor = (try? c.decodeIfPresent(Int.self, forKey: .totalMinor)) ?? 0
        }
    }
    struct ByFund: Codable, Sendable, Identifiable {
        let code: String
        let name: String
        let totalMinor: Int
        var id: String { code }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            totalMinor = (try? c.decodeIfPresent(Int.self, forKey: .totalMinor)) ?? 0
        }
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let thisYear = Calendar.current.component(.year, from: Date())
        year = (try? c.decodeIfPresent(Int.self, forKey: .year)) ?? thisYear
        let ys = (try? c.decodeIfPresent([Int].self, forKey: .years)) ?? []
        years = ys.isEmpty ? [year] : ys
        totalMinor = (try? c.decodeIfPresent(Int.self, forKey: .totalMinor)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "KES"
        byPledge = (try? c.decodeIfPresent([ByPledge].self, forKey: .byPledge)) ?? []
        byFund = (try? c.decodeIfPresent([ByFund].self, forKey: .byFund)) ?? []
        payments = (try? c.decodeIfPresent([PledgePayment].self, forKey: .payments)) ?? []
        pledgedMinor = try? c.decodeIfPresent(Int.self, forKey: .pledgedMinor)
        paidMinor = try? c.decodeIfPresent(Int.self, forKey: .paidMinor)
        remainingMinor = try? c.decodeIfPresent(Int.self, forKey: .remainingMinor)
        pledges = (try? c.decodeIfPresent([StatementPledge].self, forKey: .pledges)) ?? []
        impact = try? c.decodeIfPresent(Impact.self, forKey: .impact)
        months = (try? c.decodeIfPresent([MonthStatus].self, forKey: .months)).flatMap { $0.isEmpty ? nil : $0 }
        faithfulness = try? c.decodeIfPresent(Faithfulness.self, forKey: .faithfulness)
        season = try? c.decodeIfPresent(Season.self, forKey: .season)
        pending = (try? c.decodeIfPresent([PledgePayment].self, forKey: .pending)) ?? []
    }
    enum CodingKeys: String, CodingKey {
        case years, year, totalMinor, currency, byPledge, byFund, payments
        case pledgedMinor, paidMinor, remainingMinor, pledges
        case impact, months, faithfulness, season, pending
    }
}

private extension KeyedDecodingContainer {
    /// An integer the server may send as 12, 12.0 or "12" — nil when absent,
    /// null or unreadable. Never throws: one odd field must not blank a page.
    func flexInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: key), v.isFinite, abs(v) < 9e15 {
            return Int(v.rounded())
        }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespaces)
            if let n = Int(t) { return n }
            if let v = Double(t), v.isFinite, abs(v) < 9e15 { return Int(v.rounded()) }
        }
        return nil
    }

    /// A number the server may send as 42, 42.5 or "42.5" — nil when
    /// absent, null, unreadable or not finite. Never throws.
    func flexDouble(_ key: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: key), v.isFinite { return v }
        if let s = try? decodeIfPresent(String.self, forKey: key),
           let v = Double(s.trimmingCharacters(in: .whitespaces)), v.isFinite { return v }
        return nil
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
