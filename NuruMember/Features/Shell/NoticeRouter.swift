// One router for a tapped notice (pathway docs/EXPERIENCE.md §7.2 #3, §7.1
// rule 1): a row in the inbox and a tapped iOS notification land in the same
// place, decided here once. The two used to keep tables of their own — a Live
// notice opened the player from a banner but fell through to a sheet in the
// inbox (a greeting, journey chips, "Continue my journey"), and a Read with a
// Friend notice went to Plans from one and nowhere from the other.
//
// `route(_:)` is pure (the tests pin every template family); `open(_:tabs:)`
// carries a route out on the TabRouter. A notice with nowhere to go comes back
// `.itself`: the inbox shows the notice alone, a banner opens the inbox.
import Foundation

/// What a notice says about where it points — read from an inbox row's
/// payload, or from the userInfo a banner carries (LocalNotifier writes it
/// with `userInfo`, so the keys live in one place).
struct NoticeTarget: Equatable {
    var template: String
    var announcementId: String? = nil
    var moduleId: String? = nil
    var levelNumber: Int? = nil
    var inviteToken: String? = nil
    var departmentId: String? = nil
    var transactionId: String? = nil
    var scheduleId: String? = nil
    var pledgeId: String? = nil
    /// A Live notice's stream (`live_stream_started`, `live_guest_invite`).
    var streamId: String? = nil
    /// The notice's own title — an ended Live is named by it.
    var title: String? = nil
}

extension NoticeTarget {
    init(_ n: NotificationRow) {
        let p = n.payload
        // The title rides along only where a route needs it (a Live's name) —
        // a banner's userInfo carries no more of a notice than routing does.
        self.init(template: n.template, announcementId: p?.announcementId, moduleId: p?.moduleId,
                  levelNumber: p?.levelNumber, inviteToken: p?.inviteToken, departmentId: p?.departmentId,
                  transactionId: p?.transactionId, scheduleId: p?.scheduleId, pledgeId: p?.pledgeId,
                  streamId: p?.streamId, title: n.template.hasPrefix("live") ? p?.title : nil)
    }

    /// From a tapped banner's userInfo — absent keys and the empty strings
    /// LocalNotifier writes for them read the same. The local notifications
    /// LocalNotifier posts carry camelCase ids; a real push carries the
    /// notification's own snake_case keys, its numbers as strings
    /// (notification sounds, 2026-09-28) — both read the same here.
    init(userInfo info: [AnyHashable: Any]) {
        func text(_ camel: String, _ snake: String? = nil) -> String? {
            for key in [camel, snake].compactMap({ $0 }) {
                if let s = info[key] as? String, !s.isEmpty { return s }
            }
            return nil
        }
        let level = (info["levelNumber"] as? Int) ?? (info["level_number"] as? Int)
            ?? Int(text("levelNumber", "level_number") ?? "")
        self.init(template: text("template") ?? "", announcementId: text("announcementId", "announcement_id"),
                  moduleId: text("moduleId", "module_id"), levelNumber: level.flatMap { $0 > 0 ? $0 : nil },
                  inviteToken: text("inviteToken", "invite_token"), departmentId: text("departmentId", "department_id"),
                  transactionId: text("transactionId", "transaction_id"), scheduleId: text("scheduleId", "schedule_id"),
                  pledgeId: text("pledgeId", "pledge_id"), streamId: text("streamId", "stream_id"), title: text("title"))
    }

    /// The routing keys a banner carries, so its tap can land on the exact
    /// target. The mirror of `init(userInfo:)`.
    var userInfo: [String: Any] {
        ["template": template,
         "announcementId": announcementId ?? "",
         "moduleId": moduleId ?? "",
         "levelNumber": levelNumber ?? 0,
         "inviteToken": inviteToken ?? "",
         "departmentId": departmentId ?? "",
         // Giving: the failed gift (Cycle 3) or recurring gift (Cycle 4) a tap opens.
         "transactionId": transactionId ?? "",
         "scheduleId": scheduleId ?? "",
         // Partners (Cycle 5): the pledge a pledge notice opens.
         "pledgeId": pledgeId ?? "",
         // Nuru Live: the stream a Live notice opens (or says has ended).
         "streamId": streamId ?? "",
         "title": title ?? ""]
    }
}

/// Where a tapped notice lands — always inside the tab that owns it, so the
/// bottom bar tells the truth about where the member is.
enum NoticeRoute: Equatable {
    /// pledge_* and the pledge collector's notices — that pledge (Give ▸ Partners).
    case pledge(String)
    /// A failed gift's result, or a failed / paused recurring gift's sheet (Give).
    case gift(GiveLink)
    /// The announcement itself.
    case announcement(String)
    /// A module or a level, on the Pathway tab.
    case pathway(PathwayRoute)
    /// The Pathway tab itself (a reflection's review, a level notice with no number).
    case pathwayTab
    /// That department's page (You ▸ Departments).
    case department(String)
    /// The Departments list.
    case departments
    /// The Events tab.
    case events
    /// Give ▸ Partners.
    case partners
    /// Give.
    case give
    /// You ▸ Profile (badges, certificates).
    case profile
    /// A Read with a Friend invite (Plans).
    case readingInvite(String)
    /// The Read with a Friend hub (Plans).
    case readWithFriend
    /// A Live notice: the player while the stream is live, a calm "This Live
    /// has ended" once it's over.
    case live(streamId: String?, title: String?)
    /// Nowhere to go: the notice itself.
    case itself
}

enum NoticeRouter {
    /// The one decision. Tried in order; the first that holds is where it lands.
    static func route(_ t: NoticeTarget) -> NoticeRoute {
        let tpl = t.template
        if let id = PledgeLink.from(template: tpl, pledgeId: t.pledgeId) { return .pledge(id) }
        if let link = GiveLink.from(template: tpl, transactionId: t.transactionId, scheduleId: t.scheduleId) {
            return .gift(link)
        }
        if let id = filled(t.announcementId) { return .announcement(id) }
        if let id = filled(t.moduleId) { return .pathway(.module(id)) }
        if tpl.hasPrefix("level"), let n = t.levelNumber, n > 0 { return .pathway(.level(n)) }
        // Departments (PARTNERS_PROGRAMME §4): the page itself when the
        // notice names it, else the list.
        if tpl.hasPrefix("serve_request") || tpl.hasPrefix("department") {
            return filled(t.departmentId).map { .department($0) } ?? .departments
        }
        if tpl.hasPrefix("event") { return .events }
        if tpl.hasPrefix("pledge") { return .partners }   // pledge_due_soon / _overdue / _fulfilled (§3), no id
        if tpl.hasPrefix("giving") || tpl.hasPrefix("payment") { return .give }
        if tpl.hasPrefix("badge") || tpl.hasPrefix("certificate") { return .profile }
        if tpl.hasPrefix("level") || tpl.hasPrefix("reflection") { return .pathwayTab }
        // Read with a Friend — the invite a nuru://join/{token} link opens;
        // the other plan_group_* pings land on the hub.
        if tpl == "plan_group_invite_received", let token = filled(t.inviteToken) { return .readingInvite(token) }
        if tpl.hasPrefix("plan_group") { return .readWithFriend }
        if tpl.hasPrefix("live") { return .live(streamId: filled(t.streamId), title: filled(t.title)) }
        return .itself
    }

    private static func filled(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }
}

@MainActor
extension NoticeRouter {
    /// Carries a route out — the inbox and a tapped banner both come here.
    /// False when the notice has nowhere to go: the caller shows the notice
    /// itself (the inbox's sheet; a banner opens the inbox).
    @discardableResult
    static func open(_ route: NoticeRoute, tabs: TabRouter) -> Bool {
        switch route {
        case .pledge(let id): tabs.openPledge(id)
        case .gift(let link): tabs.openGive(link: link)
        case .announcement(let id): tabs.openAnnouncement(id)
        case .pathway(let r): tabs.openPathway(r)
        case .pathwayTab: tabs.selected = .pathway
        case .department(let id): tabs.openDepartment(id)
        case .departments: tabs.openYou(.departments)
        case .events: tabs.openEvents()
        case .partners: tabs.openPartners()
        case .give: tabs.openGive()
        case .profile: tabs.openYou(.profile)
        case .readingInvite(let token): tabs.openReadingInvite(token)
        case .readWithFriend: tabs.openPlans(.readWithFriendHub)
        case let .live(streamId, title):
            Task { await LiveDiscoveryCenter.shared.openNotice(streamId: streamId, title: title) }
        case .itself: return false
        }
        return true
    }
}
