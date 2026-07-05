// Typed endpoint facade over APIClient — the native counterpart of the NuruApi
// object in packages/mobile/src/api/client.ts. Screens call these, never the raw
// client. Only the endpoints needed by the current slice are wired; the rest are
// ported screen-by-screen (see PORT_STATUS.md).
import Foundation

enum MemberAPI {
    // MARK: Auth

    /// POST /auth/login — may yield a 2FA challenge instead of a session.
    static func login(email: String, password: String) async throws -> LoginResult {
        try await APIClient.shared.login(email: email, password: password)
    }

    static func completeMfa(mfaToken: String, code: String) async throws -> Session {
        try await APIClient.shared.completeMfa(mfaToken: mfaToken, code: code)
    }

    /// POST /auth/register — create an account and sign in.
    static func register(fullName: String, email: String, password: String) async throws -> Session {
        try await APIClient.shared.register(fullName: fullName, email: email, password: password)
    }

    /// POST /auth/password/forgot — request a reset. In dev the server returns a
    /// `dev_token` (no email provider) so the flow can continue inline.
    static func forgotPassword(_ email: String) async throws -> String? {
        struct Body: Encodable { let email: String }
        struct Res: Decodable { let sent: Bool; let devToken: String? }
        return try await APIClient.shared.post("auth/password/forgot", body: Body(email: email), as: Res.self).devToken
    }

    /// POST /auth/password/reset — set a new password from a reset token.
    static func resetPassword(token: String, newPassword: String) async throws {
        struct Body: Encodable { let token: String; let newPassword: String }
        _ = try await APIClient.shared.post("auth/password/reset",
                                            body: Body(token: token, newPassword: newPassword), as: EmptyResponse.self)
    }

    // MARK: Profile

    /// GET /me — the signed-in member's profile + enrollment summary.
    static func me() async throws -> MeResponse {
        try await APIClient.shared.get("me", as: MeResponse.self)
    }

    // MARK: Security — TOTP two-factor (§5.3)

    /// POST /auth/mfa/enroll — begin 2FA enrollment; returns the secret to confirm.
    static func enrollMfa() async throws -> MfaEnrollment {
        struct Empty: Encodable {}
        return try await APIClient.shared.post("auth/mfa/enroll", body: Empty(), as: MfaEnrollment.self)
    }
    /// POST /auth/mfa/verify — confirm enrollment with a 6-digit code (turns 2FA on).
    static func verifyMfa(code: String) async throws {
        struct Body: Encodable { let code: String }
        _ = try await APIClient.shared.post("auth/mfa/verify", body: Body(code: code), as: EmptyResponse.self)
    }
    /// POST /auth/mfa/disable — turn 2FA off (requires a current TOTP/recovery code).
    static func disableMfa(code: String) async throws {
        struct Body: Encodable { let code: String }
        _ = try await APIClient.shared.post("auth/mfa/disable", body: Body(code: code), as: EmptyResponse.self)
    }

    // MARK: Privacy — approximate location sharing (§proximity; coarse geohash only)

    /// POST /me/location — share an approximate fix (server keeps only a coarse geohash).
    static func shareLocation(lat: Double, lng: Double) async throws {
        struct Body: Encodable { let lat: Double; let lng: Double }
        _ = try await APIClient.shared.post("me/location", body: Body(lat: lat, lng: lng), as: EmptyResponse.self)
    }
    /// DELETE /me/location — opt out; erases the stored coarse location.
    static func stopSharingLocation() async throws {
        _ = try await APIClient.shared.delete("me/location", as: EmptyResponse.self)
    }

    // MARK: Home (server-driven dashboard)

    /// GET /me/rhythm/today — today's three daily rhythms.
    static func rhythmToday() async throws -> RhythmToday {
        try await APIClient.shared.get("me/rhythm/today", as: RhythmToday.self)
    }

    /// GET /me/home/next-action — the next-best-action hero card (may be null).
    static func nextAction() async throws -> NextAction? {
        try await APIClient.shared.get("me/home/next-action", as: NextActionEnvelope.self).action
    }

    /// POST /me/rhythm/complete — mark a rhythm done for today (idempotent).
    static func completeRhythm(_ kind: String) async throws -> RhythmToday {
        struct Body: Encodable { let kind: String }
        return try await APIClient.shared.post("me/rhythm/complete", body: Body(kind: kind), as: RhythmToday.self)
    }

    /// GET /me/achievements — used on Home for the streak count.
    static func achievements() async throws -> Achievements {
        try await APIClient.shared.get("me/achievements", as: Achievements.self)
    }

    /// GET /me/notifications — Home needs only the unread count.
    static func unreadNotifications() async throws -> Int {
        struct Res: Decodable { let unread: Int }
        return try await APIClient.shared.get("me/notifications", as: Res.self).unread
    }

    /// GET /me/notifications — the full notification center (rows + unread count).
    static func notifications() async throws -> (rows: [NotificationRow], unread: Int) {
        struct Res: Decodable { let data: [NotificationRow]; let unread: Int }
        let r = try await APIClient.shared.get("me/notifications", as: Res.self)
        return (r.data, r.unread)
    }

    /// POST /me/notifications/read — mark some (or all) notifications read.
    static func markNotificationsRead(_ ids: [String]? = nil) async throws {
        struct Body: Encodable { let ids: [String]? }
        _ = try await APIClient.shared.post("me/notifications/read", body: Body(ids: ids), as: EmptyResponse.self)
    }

    /// GET /me/scores — the five growth scores + weighted overall.
    static func scores() async throws -> ScoresSummary {
        try await APIClient.shared.get("me/scores", as: ScoresSummary.self)
    }

    /// GET /me/home/greeting — the warm daily-greeting line under the greeting.
    static func dailyGreeting() async throws -> String {
        struct Res: Decodable { let greeting: String }
        return try await APIClient.shared.get("me/home/greeting", as: Res.self).greeting
    }

    /// GET /me/home/verse — the tailored "Verse for today".
    static func homeVerse() async throws -> TailoredVerse {
        try await APIClient.shared.get("me/home/verse", as: TailoredVerse.self)
    }

    /// GET /scripture?ref= — fetch a passage's text + translation.
    static func scripture(_ ref: String) async throws -> ScripturePassage {
        try await APIClient.shared.get("scripture", query: ["ref": ref], as: ScripturePassage.self)
    }

    /// GET /me/home/verse/reactions — community reaction counts for today's verse.
    static func verseReactions() async throws -> VerseReactions {
        try await APIClient.shared.get("me/home/verse/reactions", as: VerseReactions.self)
    }

    /// POST /me/home/verse/reactions — set my reaction (one per member/day).
    @discardableResult
    static func setVerseReaction(_ emoji: String) async throws -> VerseReactions {
        struct Body: Encodable { let emoji: String }
        return try await APIClient.shared.post("me/home/verse/reactions", body: Body(emoji: emoji), as: VerseReactions.self)
    }

    /// PUT /me/verses — save the verse-of-the-day to the library (one-tap Save).
    static func saveVerseQuick(reference: String, version: String?, text: String?) async throws {
        try await saveVerse(savedVerseId: UUID().uuidString, reference: reference, version: version, verseText: text)
    }

    // MARK: Pathway (levels · modules · quiz — server-authoritative gating §1.9)

    /// GET /me/pathway — the member's level trail with per-level progress + status.
    static func pathway() async throws -> PathwaySummary {
        try await APIClient.shared.get("me/pathway", as: PathwaySummary.self)
    }

    /// GET /levels/{n}/modules — the module trail for a level.
    static func levelModules(_ levelNumber: Int) async throws -> [LevelModule] {
        try await APIClient.shared.get("levels/\(levelNumber)/modules", as: Envelope<LevelModule>.self).data
    }

    /// GET /modules/{id} — full lesson + evaluation metadata. Server refuses
    /// content above the member's current level (§1.9); we also honour `locked`.
    static func module(_ moduleId: String) async throws -> ModuleDetail {
        try await APIClient.shared.get("modules/\(moduleId)", as: ModuleDetail.self)
    }

    /// POST /modules/{id}/complete — finish a non-quiz module (optional reflection).
    static func completeModule(_ moduleId: String, reflectionText: String? = nil) async throws -> CompleteResult {
        struct Body: Encodable { let reflectionText: String? }
        return try await APIClient.shared.post("modules/\(moduleId)/complete",
                                               body: Body(reflectionText: reflectionText), as: CompleteResult.self)
    }

    /// GET /modules/{id}/quiz — the server-assembled quiz (answer signal stripped).
    static func quiz(_ moduleId: String) async throws -> AssembledQuiz {
        try await APIClient.shared.get("modules/\(moduleId)/quiz", as: AssembledQuiz.self)
    }

    /// POST /modules/{id}/quiz/attempts — submit answers; scored server-side (§3.7).
    /// `clientMutationId` keeps the attempt idempotent on replay (§2.1/§3.6).
    static func submitQuiz(_ moduleId: String, clientMutationId: String,
                           answers: [QuizAnswer]) async throws -> QuizResult {
        struct Body: Encodable { let clientMutationId: String; let answers: [QuizAnswer] }
        return try await APIClient.shared.post("modules/\(moduleId)/quiz/attempts",
                                               body: Body(clientMutationId: clientMutationId, answers: answers),
                                               as: QuizResult.self)
    }
}

extension MemberAPI {
    // MARK: Growth — daily rhythm & Word
    //
    // NOTE: the writes here (reflection, practice, plan/segment completion, prayer
    // upsert/delete, verse save/delete) currently go online-first. They are
    // retrofitted onto `SyncEngine.writeThrough` (offline queue, §1.7/§3.6) when
    // the offline-engine phase lands — the RN app queued these.

    /// GET /growth/devotional — today's devotional (+ my saved reflection if any).
    static func devotional() async throws -> Devotional {
        try await APIClient.shared.get("growth/devotional", as: Devotional.self)
    }

    /// POST /growth/devotional/reflection — save a reflection; marks the Reflection rhythm.
    @discardableResult
    static func saveDevotionalReflection(devotionalId: String, body: String) async throws -> Bool {
        struct Body: Encodable { let devotionalId: String; let body: String }
        struct Saved: Decodable { let saved: Bool }
        return try await APIClient.shared.post("growth/devotional/reflection",
                                               body: Body(devotionalId: devotionalId, body: body), as: Saved.self).saved
    }

    /// GET /growth/memory-verses — the member's memory-verse set with status.
    static func memoryVerses() async throws -> [MemoryVerseRow] {
        try await APIClient.shared.get("growth/memory-verses", as: Envelope<MemoryVerseRow>.self).data
    }

    /// POST /growth/memory-verses/practice — log a practice attempt (match %).
    static func practiceVerse(_ memoryVerseId: String, matchPct: Int) async throws {
        struct Body: Encodable { let memoryVerseId: String; let matchPct: Int }
        _ = try await APIClient.shared.post("growth/memory-verses/practice",
                                            body: Body(memoryVerseId: memoryVerseId, matchPct: matchPct), as: EmptyResponse.self)
    }

    /// GET /growth/plans — the reading-plan catalogue with enrolment state.
    static func plans() async throws -> [ReadingPlanRow] {
        try await APIClient.shared.get("growth/plans", as: Envelope<ReadingPlanRow>.self).data
    }

    /// GET /growth/resources — the library (books, audio, video, articles).
    static func resources() async throws -> [ResourceRow] {
        try await APIClient.shared.get("growth/resources", as: Envelope<ResourceRow>.self).data
    }

    // MARK: Nuru assistant (AI companion — POST is provider-backed, may be offline)

    /// GET /assistant/history — this member's prior assistant turns.
    static func assistantHistory() async throws -> [AssistantMessage] {
        struct H: Decodable { let messages: [AssistantMessage] }
        return try await APIClient.shared.get("assistant/history", as: H.self).messages
    }

    /// POST /assistant/chat — send the running transcript, get Nuru's reply.
    /// `conversationId` lets the server ground on messages the member can access
    /// and `contextLimit` caps how many it reads; both are OMITTED from the JSON
    /// when nil (synthesized Encodable uses encodeIfPresent — the server's zod
    /// schema rejects explicit nulls), so existing call sites' wire is unchanged.
    static func assistantChat(_ messages: [AssistantMessage],
                              conversationId: String? = nil,
                              contextLimit: Int? = nil) async throws -> String {
        struct Body: Encodable { let messages: [AssistantMessage]; let conversationId: String?; let contextLimit: Int? }
        struct Reply: Decodable { let reply: String }
        return try await APIClient.shared.post("assistant/chat",
            body: Body(messages: messages, conversationId: conversationId, contextLimit: contextLimit),
            as: Reply.self).reply
    }

    /// GET /growth/plans/{id} — a plan with its day-by-day breakdown.
    static func plan(_ id: String) async throws -> ReadingPlanDetail {
        try await APIClient.shared.get("growth/plans/\(id)", as: ReadingPlanDetail.self)
    }

    /// POST /growth/plans/{id}/start — enrol in a plan.
    static func startPlan(_ id: String) async throws {
        _ = try await APIClient.shared.postEmpty("growth/plans/\(id)/start", as: EmptyResponse.self)
    }

    /// POST /growth/plans/{id}/complete-day — mark a whole day done.
    static func completePlanDay(_ id: String, dayNumber: Int) async throws {
        struct Body: Encodable { let dayNumber: Int }
        _ = try await APIClient.shared.post("growth/plans/\(id)/complete-day",
                                            body: Body(dayNumber: dayNumber), as: EmptyResponse.self)
    }

    /// POST /growth/segments/{id}/complete — mark one plan-day segment done.
    @discardableResult
    static func completePlanSegment(_ segmentId: String) async throws -> SegmentCompleteResult {
        try await APIClient.shared.postEmpty("growth/segments/\(segmentId)/complete", as: SegmentCompleteResult.self)
    }

    // MARK: Prayer journal

    /// GET /me/prayers — the member's private prayer journal.
    static func prayers() async throws -> [PrayerEntry] {
        try await APIClient.shared.get("me/prayers", as: Envelope<PrayerEntry>.self).data
    }

    /// PUT /me/prayers — create or update an entry (idempotent on entry_id).
    static func upsertPrayer(entryId: String, body: String, title: String? = nil,
                             isAnswered: Bool = false, answeredNote: String? = nil) async throws {
        struct Body: Encodable {
            let entryId: String; let title: String?; let body: String
            let isAnswered: Bool; let answeredNote: String?; let clientMutationId: String
        }
        _ = try await APIClient.shared.put("me/prayers",
            body: Body(entryId: entryId, title: title, body: body, isAnswered: isAnswered,
                       answeredNote: answeredNote, clientMutationId: UUID().uuidString), as: EmptyResponse.self)
    }

    /// DELETE /me/prayers/{id}.
    static func deletePrayer(_ entryId: String) async throws {
        _ = try await APIClient.shared.delete("me/prayers/\(entryId)", as: EmptyResponse.self)
    }

    // MARK: Verse library (saved verses)

    /// GET /me/verses — the member's saved-verse library.
    static func verses() async throws -> [SavedVerse] {
        try await APIClient.shared.get("me/verses", as: Envelope<SavedVerse>.self).data
    }

    /// PUT /me/verses — save/update a verse (idempotent on saved_verse_id).
    static func saveVerse(savedVerseId: String, reference: String, version: String? = nil,
                          verseText: String? = nil, note: String? = nil) async throws {
        struct Body: Encodable {
            let savedVerseId: String; let reference: String; let version: String?
            let verseText: String?; let note: String?; let clientMutationId: String
        }
        _ = try await APIClient.shared.put("me/verses",
            body: Body(savedVerseId: savedVerseId, reference: reference, version: version,
                       verseText: verseText, note: note, clientMutationId: UUID().uuidString), as: EmptyResponse.self)
    }

    /// DELETE /me/verses/{id}.
    static func deleteVerse(_ savedVerseId: String) async throws {
        _ = try await APIClient.shared.delete("me/verses/\(savedVerseId)", as: EmptyResponse.self)
    }
}

extension MemberAPI {
    // MARK: Events & calendar

    /// GET /calendar?from=&to= — occurrences in a date window.
    static func calendar(from: String, to: String) async throws -> [CalendarOccurrence] {
        try await APIClient.shared.get("calendar", query: ["from": from, "to": to], as: Envelope<CalendarOccurrence>.self).data
    }

    /// GET /home/featured-event — the admin-featured event (may be null).
    static func featuredEvent() async throws -> FeaturedEvent? {
        struct Env: Decodable { let data: FeaturedEvent? }
        return try await APIClient.shared.get("home/featured-event", as: Env.self).data
    }

    /// GET /calendar/series — followable event series.
    static func eventSeries() async throws -> [EventSeries] {
        try await APIClient.shared.get("calendar/series", as: Envelope<EventSeries>.self).data
    }

    /// POST /calendar/series/{id}/follow — toggle following a series.
    static func toggleSeriesFollow(_ id: String) async throws -> SeriesFollowResult {
        try await APIClient.shared.postEmpty("calendar/series/\(id)/follow", as: SeriesFollowResult.self)
    }

    /// GET /home/featured-announcement — the admin-featured announcement (may be null).
    static func featuredAnnouncement() async throws -> FeaturedAnnouncement? {
        struct Env: Decodable { let data: FeaturedAnnouncement? }
        return try await APIClient.shared.get("home/featured-announcement", as: Env.self).data
    }

    /// GET /me/announcements — the member's announcements.
    static func myAnnouncements() async throws -> [MyAnnouncement] {
        try await APIClient.shared.get("me/announcements", as: Envelope<MyAnnouncement>.self).data
    }

    /// GET /announcements/{id} — full announcement (carousel images + body).
    static func announcement(_ id: String) async throws -> AnnouncementDetail {
        try await APIClient.shared.get("announcements/\(id)", as: AnnouncementDetail.self)
    }

    /// POST /announcements/{id}/open — mark opened (best-effort).
    static func openAnnouncement(_ id: String) async {
        _ = try? await APIClient.shared.postEmpty("announcements/\(id)/open", as: EmptyResponse.self)
    }

    // MARK: Home dashboard extras

    /// GET /home/welcome-video — the homepage welcome video (may be null).
    static func welcomeVideo() async throws -> WelcomeVideo? {
        try await APIClient.shared.get("home/welcome-video", as: WelcomeVideo?.self)
    }

    /// POST /media/{id}/reactions — toggle a reaction on a media asset.
    @discardableResult
    static func toggleMediaReaction(_ mediaAssetId: String, emoji: String) async throws -> ReactionToggleResult {
        struct Body: Encodable { let emoji: String }
        return try await APIClient.shared.post("media/\(mediaAssetId)/reactions", body: Body(emoji: emoji), as: ReactionToggleResult.self)
    }

    /// GET /home/featured-cell — "This week at Nuru" (may be null).
    static func featuredCell() async throws -> FeaturedCell? {
        try await APIClient.shared.get("home/featured-cell", as: FeaturedCell?.self)
    }

    /// GET /growth/mentor — the member's assigned discipler + meeting notes.
    static func mentor() async throws -> MentorInfo {
        try await APIClient.shared.get("growth/mentor", as: MentorInfo.self)
    }

    /// GET /home/disciplers — "Meet your discipler" carousel.
    static func disciplers() async throws -> [Discipler] {
        try await APIClient.shared.get("home/disciplers", as: Envelope<Discipler>.self).data
    }

    /// GET /home/prayer-wall — prayer-wall posts for the Home carousel.
    static func prayerWallHome() async throws -> [PrayerWallPost] {
        try await APIClient.shared.get("home/prayer-wall", as: Envelope<PrayerWallPost>.self).data
    }

    /// GET /me/cell-summary — the member's cell card.
    static func cellSummary() async throws -> CellSummary {
        try await APIClient.shared.get("me/cell-summary", as: CellSummary.self)
    }

    /// GET /moments — curated photo gallery.
    static func moments() async throws -> [Moment] {
        try await APIClient.shared.get("moments", as: Envelope<Moment>.self).data
    }

    /// GET /events/{id} — full event detail.
    static func event(_ id: String) async throws -> EventDetail {
        try await APIClient.shared.get("events/\(id)", as: EventDetail.self)
    }

    /// POST /events/{id}/rsvp — set the member's RSVP.
    static func rsvp(_ eventId: String, status: String) async throws {
        struct Body: Encodable { let status: String }
        _ = try await APIClient.shared.post("events/\(eventId)/rsvp", body: Body(status: status), as: EmptyResponse.self)
    }

    /// GET /me/rsvps — the member's RSVPs.
    static func myRsvps() async throws -> [MyRsvp] {
        try await APIClient.shared.get("me/rsvps", as: Envelope<MyRsvp>.self).data
    }

    // MARK: Event wall ("Who's coming" buzz posts)

    /// GET /events/{id}/posts — the event's buzz posts, newest first.
    static func eventPosts(_ eventId: String) async throws -> [EventPost] {
        try await APIClient.shared.get("events/\(eventId)/posts", as: Envelope<EventPost>.self).data
    }

    /// POST /events/{id}/posts — post to the wall. Idempotent on both the
    /// client-minted post_id and client_mutation_id (server dedupes replays).
    @discardableResult
    static func createEventPost(_ eventId: String, postId: String, body: String) async throws -> EventPostCreateResult {
        struct Body: Encodable { let postId: String; let body: String; let clientMutationId: String }
        return try await APIClient.shared.post("events/\(eventId)/posts",
            body: Body(postId: postId, body: body, clientMutationId: UUID().uuidString),
            as: EventPostCreateResult.self)
    }

    /// POST /events/{id}/posts/{postId}/react — set/switch (kind) or clear (nil)
    /// the member's single reaction. `kind` must serialize as an explicit JSON
    /// null when clearing (the server's schema requires the key).
    static func reactToEventPost(_ eventId: String, postId: String, kind: String?) async throws -> EventPostReactionResult {
        struct Body: Encodable {
            let kind: String?
            enum CodingKeys: String, CodingKey { case kind }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                if let kind { try c.encode(kind, forKey: .kind) } else { try c.encodeNil(forKey: .kind) }
            }
        }
        return try await APIClient.shared.post("events/\(eventId)/posts/\(postId)/react",
            body: Body(kind: kind), as: EventPostReactionResult.self)
    }

    // MARK: Giving (online-only, §5.6 — money is never queued)

    /// GET /giving/history — the member's gift history.
    static func givingHistory() async throws -> [GivingRecord] {
        try await APIClient.shared.get("giving/history", as: Envelope<GivingRecord>.self).data
    }

    /// POST /giving/intents — create a real gift intent (server-authoritative).
    static func giving(fund: String, amountMinor: Int, currency: String,
                       method: String, phoneNumber: String? = nil) async throws -> GivingIntentResult {
        struct Body: Encodable {
            let fund: String; let amountMinor: Int; let currency: String
            let method: String; let phoneNumber: String?; let idempotencyKey: String
        }
        return try await APIClient.shared.post("giving/intents",
            body: Body(fund: fund, amountMinor: amountMinor, currency: currency,
                       method: method, phoneNumber: phoneNumber, idempotencyKey: UUID().uuidString),
            as: GivingIntentResult.self)
    }

    /// GET /giving/transactions/{id} — full gift detail incl. the ledger trail.
    static func givingDetail(_ id: String) async throws -> GivingDetail {
        try await APIClient.shared.get("giving/transactions/\(id)", as: GivingDetail.self)
    }

    /// GET /me/gifts — the member's spiritual-gifts profile.
    static func myGifts() async throws -> MyGifts {
        try await APIClient.shared.get("me/gifts", as: MyGifts.self)
    }

    /// GET /gifts/questions — the (possibly AI-personalized) Likert question set.
    static func giftQuestions() async throws -> GiftQuestionSet {
        try await APIClient.shared.get("gifts/questions", as: GiftQuestionSet.self)
    }

    /// POST /gifts/assessments — submit Likert answers; returns the new profile.
    static func submitGifts(setId: String, clientMutationId: String, answers: [GiftAnswerInput]) async throws -> MyGifts {
        struct Body: Encodable { let clientMutationId: String; let setId: String; let answers: [GiftAnswerInput] }
        return try await APIClient.shared.post(
            "gifts/assessments",
            body: Body(clientMutationId: clientMutationId, setId: setId, answers: answers),
            as: MyGifts.self
        )
    }

    /// GET /giving/schedules — the member's recurring gifts.
    static func schedules() async throws -> [GivingSchedule] {
        try await APIClient.shared.get("giving/schedules", as: Envelope<GivingSchedule>.self).data
    }

    /// POST /giving/schedules/{id}/cancel.
    static func cancelSchedule(_ id: String) async throws {
        _ = try await APIClient.shared.postEmpty("giving/schedules/\(id)/cancel", as: EmptyResponse.self)
    }

    // MARK: Chat

    /// GET /chat/conversations?scope=mine — the member's inbox (Spaces/DMs/Groups).
    static func chatInbox() async throws -> ChatInbox {
        try await APIClient.shared.get("chat/conversations", query: ["scope": "mine"], as: ChatInbox.self)
    }

    /// GET /chat/conversations/{id} — a thread with its messages.
    static func chatConversation(_ id: String) async throws -> ChatThreadDetail {
        try await APIClient.shared.get("chat/conversations/\(id)", as: ChatThreadDetail.self)
    }

    /// POST /chat/conversations/{id}/messages — send a text message.
    static func sendChatMessage(_ conversationId: String, body: String) async throws {
        struct Body: Encodable { let messageId: String; let body: String; let msgType: String; let clientMutationId: String }
        _ = try await APIClient.shared.post("chat/conversations/\(conversationId)/messages",
            body: Body(messageId: UUID().uuidString, body: body, msgType: "text", clientMutationId: UUID().uuidString),
            as: EmptyResponse.self)
    }

    /// POST /chat/conversations/{id}/read — mark the thread read.
    static func markChatRead(_ conversationId: String) async throws {
        _ = try await APIClient.shared.postEmpty("chat/conversations/\(conversationId)/read", as: EmptyResponse.self)
    }

    /// GET /chat/people — the member directory (everyone the caller may DM,
    /// minor-safe and congregation-scoped server-side). Optional name search.
    static func chatPeople(query: String? = nil) async throws -> [ChatPerson] {
        struct Res: Decodable { let people: [ChatPerson] }
        var q: [String: String] = [:]
        if let query, !query.isEmpty { q["q"] = query }
        return try await APIClient.shared.get("chat/people", query: q, as: Res.self).people
    }

    /// POST /chat/dms — create (or return) the 1:1 DM with a member.
    /// Body key on the wire is `user_id`; the server dedupes an existing DM.
    static func createDm(peerUserId: String) async throws -> String {
        struct Body: Encodable { let userId: String }
        struct Res: Decodable { let conversationId: String }
        return try await APIClient.shared.post("chat/dms", body: Body(userId: peerUserId), as: Res.self).conversationId
    }

    /// POST /chat/broadcast — staff only (Instructor+; the server 403s Students):
    /// ONE message delivered to every active member of the congregation as an
    /// individual DM from the sender — replies come back as normal 1:1 threads.
    /// May carry an image (`msgType: "image"` + `attachmentUrl` from the
    /// sign-and-upload flow below); `body` is then the caption. Returns how many
    /// members it reached. Replays of the same clientMutationId are server-side
    /// no-ops (§3.6).
    static func broadcast(body: String, attachmentUrl: String? = nil, msgType: String = "text",
                          clientMutationId: String = UUID().uuidString) async throws -> Int {
        struct Body: Encodable {
            let body: String; let msgType: String; let attachmentUrl: String?; let clientMutationId: String
        }
        struct Res: Decodable { let sent: Int }
        return try await APIClient.shared.post("chat/broadcast",
            body: Body(body: body, msgType: msgType, attachmentUrl: attachmentUrl,
                       clientMutationId: clientMutationId), as: Res.self).sent
    }

    // MARK: Chat attachments (bytes go straight to Cloudinary, never our server — §4.5)

    /// POST /chat/attachments/sign — broker Cloudinary signed-upload params for a
    /// chat attachment (folder is namespaced per author server-side). The client
    /// then multipart-POSTs the bytes directly to `uploadUrl`.
    static func signChatAttachment(contentType: String, kind: String = "image") async throws -> CloudinarySign {
        struct Body: Encodable { let contentType: String; let kind: String }
        return try await APIClient.shared.post("chat/attachments/sign",
            body: Body(contentType: contentType, kind: kind), as: CloudinarySign.self)
    }

    /// Multipart POST the bytes straight to Cloudinary with the server-signed
    /// params (same field set as the RN client: file + api_key + timestamp +
    /// folder + signature). Returns the delivered `secure_url`.
    static func uploadChatAttachment(sign: CloudinarySign, data: Data,
                                     filename: String, contentType: String) async throws -> String {
        guard let url = URL(string: sign.uploadUrl) else {
            throw APIError.transport("Bad Cloudinary upload URL.")
        }
        let boundary = "nuru-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var form = Data()
        func field(_ name: String, _ value: String) {
            form.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("api_key", sign.apiKey)
        field("timestamp", String(sign.timestamp))
        field("folder", sign.folder)
        field("signature", sign.signature)
        form.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        form.append(data)
        form.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (resData, response) = try await URLSession.shared.upload(for: req, from: form)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.http(status: status, code: nil, message: "Attachment upload failed.")
        }
        struct UploadResult: Decodable { let secureUrl: String }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(UploadResult.self, from: resData).secureUrl
    }

    /// POST /chat/spaces/{id}/join — follow a public space.
    static func joinChatSpace(_ conversationId: String) async throws {
        _ = try await APIClient.shared.postEmpty("chat/spaces/\(conversationId)/join", as: EmptyResponse.self)
    }

    /// POST /chat/messages/{id}/reactions — toggle an emoji reaction.
    @discardableResult
    static func toggleChatReaction(_ messageId: String, emoji: String) async throws -> Bool {
        struct Body: Encodable { let emoji: String }
        struct Res: Decodable { let on: Bool }
        return try await APIClient.shared.post("chat/messages/\(messageId)/reactions", body: Body(emoji: emoji), as: Res.self).on
    }

    // MARK: Community — Prayer Wall (public, opt-in)

    /// GET /prayer-wall?sort= — the congregation's shared prayer requests.
    static func prayerWall(sort: String = "latest") async throws -> [PrayerWallPost] {
        try await APIClient.shared.get("prayer-wall", query: ["sort": sort], as: Envelope<PrayerWallPost>.self).data
    }

    /// GET /prayer-wall/{id} — one request with its comments.
    static func prayerWallGet(_ postId: String) async throws -> PrayerWallDetail {
        try await APIClient.shared.get("prayer-wall/\(postId)", as: PrayerWallDetail.self)
    }

    /// POST /prayer-wall — share a new request.
    static func createPrayerWallPost(title: String?, body: String) async throws {
        struct Body: Encodable { let postId: String; let title: String?; let body: String; let clientMutationId: String }
        _ = try await APIClient.shared.post("prayer-wall",
            body: Body(postId: UUID().uuidString, title: title, body: body, clientMutationId: UUID().uuidString),
            as: EmptyResponse.self)
    }

    /// POST /prayer-wall/{id}/reactions — toggle an emoji (🙏 = "pray").
    @discardableResult
    static func prayerWallReact(_ postId: String, emoji: String) async throws -> Bool {
        struct Body: Encodable { let emoji: String }
        struct Res: Decodable { let on: Bool }
        return try await APIClient.shared.post("prayer-wall/\(postId)/reactions", body: Body(emoji: emoji), as: Res.self).on
    }

    /// POST /prayer-wall/{id}/comments — encourage the requester.
    static func prayerWallComment(_ postId: String, body: String) async throws {
        struct Body: Encodable { let commentId: String; let body: String; let clientMutationId: String }
        _ = try await APIClient.shared.post("prayer-wall/\(postId)/comments",
            body: Body(commentId: UUID().uuidString, body: body, clientMutationId: UUID().uuidString), as: EmptyResponse.self)
    }

    /// POST /prayer-wall/{id}/answered — author marks (un)answered.
    static func prayerWallAnswered(_ postId: String, answered: Bool) async throws {
        struct Body: Encodable { let answered: Bool }
        _ = try await APIClient.shared.post("prayer-wall/\(postId)/answered", body: Body(answered: answered), as: EmptyResponse.self)
    }

    /// DELETE /prayer-wall/{id} — author removes their request from the wall.
    static func deletePrayerWallPost(_ postId: String) async throws {
        _ = try await APIClient.shared.delete("prayer-wall/\(postId)", as: EmptyResponse.self)
    }
}

extension MemberAPI {
    // MARK: Radio (Nuru Radio station — live HLS, scheduled shows, recorded archive)
    //
    // Member routes of the backend radio module (packages/backend/src/modules/radio).
    // The public DTO strips ingest secrets; writes carry a client_event_id so
    // replays are idempotent server-side (§2.1/§3.6).

    /// GET /radio/programs — all visible non-draft programs, live-first.
    static func radioPrograms() async throws -> [RadioProgram] {
        try await APIClient.shared.get("radio/programs", as: [RadioProgram].self)
    }

    /// GET /radio/now-playing — the live program, else the next scheduled, else null.
    static func radioNowPlaying() async throws -> RadioProgram? {
        try await APIClient.shared.get("radio/now-playing", as: RadioProgram?.self)
    }

    /// GET /radio/programs/{id} — one program (404s on private/unknown).
    static func radioProgram(_ id: String) async throws -> RadioProgram {
        try await APIClient.shared.get("radio/programs/\(id)", as: RadioProgram.self)
    }

    /// GET /radio/programs/{id}/comments — non-hidden comments, newest first.
    /// Rows carry member_id only (the backend select has no author-name join).
    static func radioComments(_ programId: String) async throws -> [RadioComment] {
        try await APIClient.shared.get("radio/programs/\(programId)/comments", as: [RadioComment].self)
    }

    /// POST /radio/programs/{id}/comments — { body, client_event_id } → 201 comment row.
    @discardableResult
    static func addRadioComment(_ programId: String, body: String) async throws -> RadioComment {
        struct Body: Encodable { let body: String; let clientEventId: String }
        return try await APIClient.shared.post("radio/programs/\(programId)/comments",
            body: Body(body: body, clientEventId: UUID().uuidString), as: RadioComment.self)
    }

    /// POST /radio/programs/{id}/react — { kind, client_event_id } → { counts }.
    /// kind ∈ heart | amen | fire; the zod schema is strict, so client_event_id
    /// is REQUIRED (the previous player omitted it and would 400).
    static func radioReact(_ programId: String, kind: String) async throws -> RadioReactionCounts {
        struct Body: Encodable { let kind: String; let clientEventId: String }
        struct Res: Decodable { let counts: RadioReactionCounts }
        return try await APIClient.shared.post("radio/programs/\(programId)/react",
            body: Body(kind: kind, clientEventId: UUID().uuidString), as: Res.self).counts
    }

    /// POST /radio/programs/{id}/listening — live-listener presence heartbeat.
    /// The player pings this ~every 20s while actually playing a live program so
    /// the studio roster shows this member by name. Fire-and-forget.
    static func radioListening(_ programId: String) async throws {
        _ = try await APIClient.shared.postEmpty("radio/programs/\(programId)/listening", as: EmptyResponse.self)
    }
}

/// One submitted answer — `givenAnswer` is always a string per the wire contract
/// (checkbox carries a JSON array of selected ids; scale carries the number).
struct QuizAnswer: Encodable, Sendable {
    let questionId: String
    let givenAnswer: String
}

/// Cloudinary signed-upload params from POST /chat/attachments/sign. The upload
/// is a multipart POST to `uploadUrl` (…/v1_1/<cloud>/auto/upload) carrying
/// exactly these fields plus the file — mirrors the RN client's CloudinarySign.
struct CloudinarySign: Decodable, Sendable {
    let cloudName: String
    let apiKey: String
    let timestamp: Int
    let folder: String
    let signature: String
    let uploadUrl: String
}

/// Generic `{ "data": [...] }` list envelope used by several collection endpoints.
struct Envelope<T: Decodable & Sendable>: Decodable, Sendable {
    let data: [T]
}
