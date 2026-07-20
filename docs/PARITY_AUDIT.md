
## 2026-07-20 — Reading typography/spacing global pass (branch feat/reading-typography-global, this repo only)
A coordinated 4-part pass making text size AND line spacing genuinely global
(same idiom, same reach) and giving scripture ONE quote-card look everywhere
it appears, plus closing the Selah spacing round-trip the backend just shipped.

**1. Global line-spacing preference (mirrors Text size exactly).**
`Theme/NuruTheme.swift`: added `Nuru.lineSpacingKey = "nuru.lineSpacing"` +
`static var lineSpacing: CGFloat` (UserDefaults-backed, clamped 0.85–1.35 —
same idiom as `Nuru.textScale`), plus the hook SwiftUI actually needs:
`NuruReadingSpacing: ViewModifier` and `View.nuruLineSpacing(_ base: CGFloat =
4)` / `.nuruReading(_:)`, both resolving to `.lineSpacing(base *
Nuru.lineSpacing)`. `Features/Profile/SettingsView.swift`: a new "Line
spacing" segmented control beside Text size — Compact/Default/Relaxed →
0.85/1.0/1.35, `@AppStorage(Nuru.lineSpacingKey)`, each chip's own two
hairlines spaced by the chip's own multiplier so the leading difference is
visible in the picker itself, not just in body text.

**2. Reading surfaces routed through `.nuruLineSpacing(_:)`.** Swapped
`.lineSpacing(n)` → `.nuruLineSpacing(n)` (same base value, now scaled by the
preference) on: `HomeCards.swift` (HomePersonalWord, HomeEncouragementCard),
`VerseTableau.swift` (VerseTableauHeader, VerseShareCard), `EchoCard.swift`
(body + quote), `LetterView.swift` (letter body), `DevotionalView.swift`
(verse card, body paragraphs, reflection prompt), `MemoryVerseView.swift`
(current-verse hero, library row), `LessonMarkdown.swift` (paragraph, bullet,
numbered, quote card), `PlanSegmentView.swift` (Talk it Over prompt),
`ReadingPlansView.swift` (DayPassage, DayTalk, DayPrayer; DayPullQuote now
goes through VerseQuoteCard below). Left tight UI chrome alone (list-preview
snippets with `lineLimit`, banners, buttons, table grids) — text size already
reached all these same surfaces via the font helpers, so the two preferences
now cover identical ground.

**3. Shared `VerseQuoteCard`.** New in `Features/Home/HomeCards.swift`: cream
parchment card (`Nuru.surface`), left gold accent bar, hanging gold ‟ glyph,
Fraunces verse in navy, uppercase letter-spaced gray reference — built by
combining HomeEncouragementCard/HomePersonalWord's card+glyph styling with
EchoCard's accent bar (no new parchment color or quote glyph invented). Takes
optional color overrides + a `cardStyle` flag (full standalone card vs. bar+
text only, for embedding inside a container that already has its own card
chrome) so ONE component serves every context:
- **Home** — `HomeView.swift`'s "classic cream" verse-for-today fallback now
  renders `VerseQuoteCard(cardStyle: false)` inside the existing outer card.
- **Pathway lessons** — `LessonMarkdown.swift`: a blockquote whose attribution
  matches `MLMarkdown.isScriptureReference(_:)` (a conservative "Book
  chapter:verse" regex, ≤40 chars) renders as `VerseQuoteCard`; an ordinary
  blockquote (no attribution, or one that isn't a reference) keeps the plain
  `MLQuoteCard` styling — no hijacking of non-scripture quotes.
- **Plans** — `ReadingPlansView.swift`'s `DayPullQuote` (the day's
  scripture segment in `PlanSegmentView.swift`) now IS a `VerseQuoteCard`,
  tinted via the existing `readerPalette` (day/night reading mode) instead of
  fixed colors — the night-mode reading experience is preserved.

**4. Selah per-span spacing (closes the backend round-trip).**
`Models/Thought.swift`: `ThoughtSpan.spacing: Double?` (0.8–2.5 multiplier,
matches `packages/backend/src/modules/thoughts/service.ts` exactly).
`Features/Community/SelahRichEditor.swift`: `SelahSpacing` now exposes a
`multiplier` (0.85/1.0/1.35 — same 3-tier scale as the new global Settings
control) instead of raw points; `SelahRichText.paragraphStyle(forMultiplier:)`
is the one place points get computed (`anchorPoints(6) * multiplier *
Nuru.lineSpacing` — the global reading preference layers on top of the note's
own choice, exactly as the backend comment on `ThoughtSpan.spacing`
describes). `build()` applies per-span overrides via this helper; `extract()`
reads each run's `NSParagraphStyle.lineSpacing` back, and — mirroring how
bold/italic/color/font already differ-from-baseline and merge adjacent runs —
records `ThoughtSpan.spacing` only when a run's spacing differs from the
note's current document default. `RichEditorController.applySpacing` now
applies to the current **selection** (a true per-span override, like the
other toolbar traits) when there is one, and falls back to the whole note
(preserving the pre-existing "space this whole thought out" gesture) when
there isn't. `SelahEditorView.swift` passes `documentSpacing:` into
`extract()`; `SelahView.swift`'s `spanDict` now serializes `spacing` into the
sync payload the mutation queue sends to the backend — without this the
round-trip was extract-only and never actually reached the server.

**Honest limits:** (a) the Selah toolbar's "document default" spacing is
still a single device-wide `@AppStorage` (pre-existing design, not introduced
here) rather than per-thought — reopening a different note can show a
different doc-default baseline than it was written with, though any EXPLICIT
per-span override always round-trips correctly regardless. (b) `VerseTableauHeader`'s photo-tableau verse (the art-backed "beheld" rendering,
distinct from the "classic cream" fallback) keeps its own bespoke overlay
styling rather than becoming a `VerseQuoteCard`, since it renders over a
photograph with a navy scrim, not a parchment card — it does route through
`.nuruLineSpacing` per item 2 above, but is not visually identical to the
quote card. (c) `MLMarkdown.isScriptureReference` is a regex heuristic — an
attribution shaped exactly like "Book chapter:verse" but that ISN'T actually
scripture (unlikely in lesson content) would render as a verse card; this
trade-off was chosen over a more invasive "explicit scripture field" schema
change, which the lesson content model doesn't currently carry.

**Verify:** `xcodebuild -scheme NuruMember -configuration Debug -destination
"id=8265F608-4A98-4E95-9074-7C54BEC4684A" build` → BUILD SUCCEEDED; `test` →
10/10 (`ModelDecodingTests`, pre-existing suite, untouched — no new unit tests
added this session for the UI/typography changes, which have no independent
model layer to unit-test beyond what ModelDecodingTests already covers for
`Thought`/`ThoughtSpan`'s tolerant decode).

## 2026-07-20 — Read with a Friend R3 client (branch feat/read-with-friend-ui, this repo only)
Reading & Social R1 backend (pathway#392, `/v1/reading/*` — shared plan
groups, invites, public `/join/{token}` OG page) now has iOS client UI. Read
`pathway/docs/READING_SOCIAL_REDESIGN.md` §3/§6 + `docs/READING_SOCIAL_PLAN.md`
and the backend module (`packages/backend/src/modules/reading-social/{groups,
invites,tokens,publicPage,index}.ts`, read-only) for the exact wire shapes;
built in a dedicated worktree (`.worktrees/rwf`) per the two-agent isolation
instruction — never pushed, commit is local only.

**New:** `Models/ReadingSocial.swift` (tolerant DTOs — `ReadingGroupRow`,
`ReadingGroupMember`, `ReadingInviteRow`, `ReadingInvitePreview`,
`ReadingInviteAcceptResult`); `Networking/MemberAPI+ReadingSocial.swift` (the
11 new calls: create-or-get group, list/get/archive/leave, create/list/revoke
invite, invite preview/accept/decline); `Features/Grow/ReadWithFriendView.swift`
— the hub (`ReadWithFriendHubView`, my active shared groups with per-friend
"Doris · Day 3 of 7" rows), group detail (`ReadingGroupDetailView` — roster +
progress bars, invite-a-friend via a new `FriendPickerSheet` that reuses
`MemberAPI.listConnections()`, share-link, leave/archive, pending-invites
list with revoke, refetches on every appear), and the invite-preview/accept/
decline screen (`ReadingInvitePreviewView`) pushed from a deep link or a
notification tap.

**Wired:** the Plans tab's "Read with a friend" card (`ReadingPlansView.swift`
`invitationCard`) now pushes the hub instead of a static text-only `ShareLink`.
`PlanDetailView`'s "Invite" button (`ctaBar`) now creates-or-gets a real group
for that plan, mints an open invite, and hands the public
`https://pathway.nuruplace.org/join/{token}` link + a rich message ("Join me
reading "<title>" on Nuru Pathway — a N-day plan. <url>") to the system share
sheet (`presentSystemShareSheet`, the same `UIActivityViewController` pattern
`ProfileView`'s certificate share uses) — WhatsApp/social/copy/QR all read the
one URL.

**Incoming:** `nuru://join/{token}` extends the EXISTING custom-scheme
handler in `RootView.onOpenURL` (previously host-only routing for widgets) —
`host == "join"` extracts the token and calls the new
`TabRouter.openReadingInvite(token)`, which lands on Plans → the hub → the
invite-preview screen (accept joins + enrolls + connects; decline is
targeted-invite-only, matching the backend's 403 on open links). A
`plan_group_invite_received` notification tap does the SAME thing — extended
`NotifPayload`/`LocalNotifier` to carry `invite_token`/`group_id` through
`userInfo`; other `plan_group_*` templates (accepted/joined/day-completed,
no redeemable token) land on the hub instead.

**Deep-link limit (honest, not silently deferred):** only the `nuru://`
custom scheme is wired, per `docs/READING_SOCIAL_PLAN.md` §5 tier 2/3 — no
`https://pathway.nuruplace.org/join/{token}` Universal Link. That needs an
`apple-app-site-association` hosted at the domain root (backend/infra work,
out of this client-only session) PLUS an Associated Domains entitlement this
repo has never had (`docs/READING_SOCIAL_PLAN.md` §3: "no `*.entitlements`
file exists anywhere in the tree"). Until AASA ships, the public `/join/{token}`
page's own inline-script fallback (already live server-side) still opens the
app via the custom scheme when installed, or falls through to the App Store
after ~1200ms when not — the three-tier fallback the backend already built;
this client half only had to honor the scheme it defines, which it now does.

**Verify:** `xcodebuild -scheme NuruMember -configuration Debug -destination
"id=8265F608-4A98-4E95-9074-7C54BEC4684A" build` → BUILD SUCCEEDED; `test` →
10/10 (`ModelDecodingTests`, pre-existing suite, untouched — no reading-social
unit tests added this session; the DTOs are exercised by the tolerant-decode
pattern used throughout, consistent with how `ChatConnections.swift` shipped).

## Session 17c — Trail nodes keep the module number (iOS 46 / Android 2.14.0)
**PRs:** ios#57 · android#22. Field feedback: the ✓ replaced the module number
after completion (and ▶ replaced it on the next module) — members lost their
place. New treatment on BOTH apps: the number NEVER leaves the 36-unit
medallion; state moved to the fill + a 15-unit corner seal (navy check-seal =
done, lock-seal = locked, navy ring = next). iOS installed on Pastor's phone;
Jackline offline (has 45, takes 46 next connect); APK 2.14.0 on Desktop.
- **Hub numbers too (ios#58 build 47 · android#24, code-only):** the 17c fix
  covered LevelDetail but the field screenshot was the HUB — journey-rail
  circles + level-preview rows still swapped numbers for icons. Corner-seal
  treatment extended there on both apps. ALSO: build 46 never actually landed
  on the phone (devicectl said "App installed" but the device stayed on 45 —
  ALWAYS verify with `devicectl device info apps` after install); 47 verified
  on-device. Android change compile-checked only, rides the next requested APK.

## 2026-07-18 — Chat consent UI: connection requests replace unsolicited DMs (branch feat/chat-consent-ui, both member apps, client-only)
Chat Redesign C3a — the backend's C1/C2 "no unsolicited DMs" model
(`docs/CHAT_REDESIGN.md` §4, `docs/CHAT_REDESIGN_PLAN.md` C1 section in the
pathway repo, read-only) now has client UI in both member apps. Contract:
`POST /chat/connections/requests` (+`/:id/accept|/decline`, `DELETE` to
cancel), `GET /chat/connections/requests?direction=incoming|outgoing`, `GET
/chat/connections`, `POST /chat/connections/:user_id/remove|/block|/unblock`,
and `POST /chat/dms` now 403s `CONSENT_REQUIRED` (details.hint = "send a
connection request first") for a brand-new thread between two ordinary
members with no accepted connection — staff and existing threads are
unaffected (grandfathered server-side, verified by reading
`chat/service.ts#createOrGetDm` and `chat/connections.ts`, both untouched).
No backend or portal changes; pathway repo intentionally left untouched
(another agent works there per instruction).

Both apps, same state machine: **not connected** → tapping a directory
person sends a request (was: opened a DM instantly). **request sent** →
shows "Request sent" with a cancel affordance. **request received** →
surfaced in a new "Connection requests" section above Direct Messages
(accept/decline). **connected** → tap opens/creates the DM exactly as
before. A stale-cache 403 `CONSENT_REQUIRED` from `createDm` auto-offers the
connection request via an alert rather than a dead-end error. Existing DM
threads keep working untouched. Empty DM-list state is now "Connect with
someone before starting a chat." The DM segment's unread-count chip now
adds pending incoming requests to the count. Per-connection controls
(Remove connection / Block / Unblock) live in the thread header's ⋮ menu for
DM threads — **no Report**: neither app has a member-facing report/
moderation affordance to reuse (flag/remove/restore are Admin-console-only
server-side), intentionally left out rather than half-built.

This repo's half: new `Models/ChatConnections.swift` (tolerant DTOs:
`ConnectionRequestRow`, `ConnectionRow`, decision/action result shapes) and
`Networking/MemberAPI+Connections.swift` (the 8 new calls). `ChatInbox
ViewModel` (`Features/Chat/ChatView.swift`) grew `connections`/
`incomingRequests`/`outgoingRequests`/`connectionState(for:)`/
`sendConnectionRequest`/`cancelConnectionRequest`/`acceptConnectionRequest`/
`declineConnectionRequest`, and `startDm` now catches `APIError.http(_,
"CONSENT_REQUIRED", _, _)` into a `consentPrompt` alert instead of failing
silently. `PersonRow` branches on the derived `ConnectionState` for its
trailing affordance (Connect / Request sent+cancel / Wants to connect /
message icon); new `IncomingRequestRow`/`OutgoingRequestRow` above the
DIRECT MESSAGES section. `ChatThreadView`'s `ThreadHeader` gains a
`connectionMenu` (SwiftUI `Menu`) replacing the previously non-functional
(empty-action) AI sparkles button for DM threads — the peer id comes from
`ChatConversation.peerUserId`, which the inbox route already returns and the
thread already carried via navigation, so no extra network round-trip was
needed here (Android's equivalent screen needed one — see its own
PARITY_AUDIT.md entry, `GET /chat/conversations/{id}` doesn't carry
`peer_user_id`).

Verified: `xcodebuild -scheme NuruMember -configuration Debug -destination
"id=8265F608-4A98-4E95-9074-7C54BEC4684A" build` → BUILD SUCCEEDED, `...
test` → 10/10 green. Android side compiled + unit-tested green too (see the
nuru-android repo's own PARITY_AUDIT.md entry, same date). Not pushed / no
PR opened (per task instruction).

## 2026-07-18 — Chat four-tab restructure + My Discipler + Talk with My Pastor (branch feat/chat-four-tabs, this repo only, client-only)
Chat Redesign C3b. Member tabs go from (My Space · Chat · My Groups[· Broadcast])
to **My Space · Chat · My Discipler · Talk with My Pastor**[· Broadcast for
SuperAdmin, unchanged]. Contract — all four routes verified LIVE by reading
`packages/backend/src/modules/{chat,pastoral}/{index,service}.ts` in the
pathway repo (read-only; nothing there touched): `GET
/chat/discipler/conversation` (`{conversation_id}`, 404 `no_discipler`), `POST
/chat/pastoral` (`{conversation_id, pastor_user_id, source}`, 404
`no_pastor`), `GET /chat/pastoral/inbox` (password-step-up gated, same 403
shape as Broadcast), `POST /chat/spaces/:id/join-requests` (+ `GET`/`accept`/
`decline`, all live). No backend/portal changes.

**My Space** merges the old `.space` and `.group` segments (backend's
migration 161 already retypes `kind IN ('space','group')` → `type=SPACE`, so
this is a pure UI merge) into sub-sections "YOUR SPACES" / "CELL & GROUPS" /
"DISCOVER SPACES". Discover's Follow button now tries the immediate `POST
/chat/spaces/:id/join` first (today's behaviour, unchanged) and only falls
back to the reviewed `POST /chat/spaces/:id/join-requests` path (pending pill,
no dead-end error) on a 403/404/409/422 — **honest limit**: `joinSpace()` in
`chat/service.ts` has zero server-side gating today (no
`requires_join_approval` column anywhere in the schema — grepped, confirmed
absent), so every Follow still succeeds immediately exactly as before; the
fallback exists for when the server starts gating some spaces, not because
any space is gated today.

**My Discipler** — tab is live/has-content only when `GET
/me/discipleship.discipler` is non-null (reused, no re-derivation); tapping
opens `GET /chat/discipler/conversation` into `ChatThreadView` with a new
explicit `ChatThreadContext` (`.normal`/`.discipler`/`.pastoral`) threaded
through a new `ThreadRoute` navigation value — the "pass context down
explicitly" approach the task called for, since `GET
/chat/conversations/:id` still doesn't return `type`. Empty state: "A
discipler has not yet been assigned to you." **`DiscipleshipHubView` is
untouched** — its own "Message" CTA still goes through the legacy
`dm_conversation_id`/`POST /chat/dms` path. Verified by reading
`createOrGetDm`: an ordinary (non-Admin/SuperAdmin) discipler with no
accepted C3a connection would hit `CONSENT_REQUIRED` there on a first-ever
message — a pre-existing gap from the C3a work, not introduced or fixed by
this change, left for whoever next touches the Hub.

**Talk with My Pastor** — tapping calls `POST /chat/pastoral`
(create-or-open); thread renders with `ChatThreadContext.pastoral`, the
privacy line "Private pastoral conversation.", and a ⋮ menu (`pastoralMenu`
in `ChatThreadView.swift`): Lock now / Enable-Disable biometric lock / Mute /
Archive (client-side hide, `PastoralPrefs.archived`, no server call — matches
"client-side hide" in the task spec) / Privacy info (honest wording, no false
E2EE claim, matches `CHAT_REDESIGN.md`'s Security section). 404 `no_pastor`
(nothing resolves at all — rare) shows "No pastor is available for your
congregation yet."

**Biometric lock — `PastoralLock.swift`, deliberately NOT `BroadcastLock`'s
shape.** No password anywhere, nothing in the Keychain — `POST
/chat/pastoral` needs no server step-up (that's the pastor/SuperAdmin inbox's
job, not the member's own thread), so there is no password to protect.
`LAContext.evaluatePolicy(.deviceOwnerAuthentication, …)` — the non-biometric
variant, so it falls back to the device passcode when Face ID/Touch ID isn't
enrolled. Remembered-open window is **5 minutes** (Broadcast's is 15) — my
call: this guards a glance-over-the-shoulder privacy risk on the member's own
phone, not broadcast authority over the whole church, so a shorter window
felt right; documented in-code rather than silently copied. Re-locks on
`UIApplication.didEnterBackgroundNotification` (covers device-lock and
app-switch), on sign-out (`AuthStore.signOut()` → `PastoralLock.shared.reset()`,
which also forgets the remembered thread ids and mute/archive flags — the
next account on this phone starts clean), and for free on app relaunch (the
open-window state is `@Published var openUntil: Date?`, in-memory only, never
persisted). The ⋮ toggle just flips a `UserDefaults` bool
(`pastoral.lock.enabled`, **off by default** — opt-in) — enabling it does
**not** enroll a password like `BroadcastLock` does, there is none. A device
with no passcode set at all fails **open** rather than locking the member out
of their own pastoral thread forever — a deliberate judgment call, documented
in-code. The locked state (`PastoralLockedGate`) is a real branch that
**replaces** `content` in `ChatThreadView`'s view tree, not an opaque cover
over live message views — message bodies are never constructed while locked,
not just visually hidden.

**Notification preview suppression — honest finding, not a guess.** Grepped
`chat/service.ts` and `pastoral/service.ts` for every call to the `notify()`
helper: chat message sends (DM, discipler, pastoral, space — all of them)
**never call it**. Only `space_join_requested`/`space_join_accepted`/
`space_join_declined` do (both live, C1/C2), and the pastoral module never
calls `notify()` at all (only `audit()`). This app also has no real APNs push
yet (`MemberAPI.registerDevice()`'s `push_token` stays absent — needs the
paid Apple Developer Program, per existing project notes); its only
notification surface is `Notifications/LocalNotifier.swift`, which polls `GET
/me/notifications` and posts local `UNNotificationRequest`s from whatever
templates come back. **Conclusion: there is currently nothing to leak** — no
chat message of any kind produces a notification, pastoral or otherwise.
`LocalNotifier` was still extended, defensively: any future `pastoral*`
template gets the owner brief's exact locked-copy wording ("You have a new
private pastoral message.") with the body always suppressed, and the newly-
live `space_join_requested`/`space_join_accepted`/`space_join_declined` +
`connection*` templates got real titles instead of falling through to the
generic "Nuru Pathway". This is forward-compatible readiness, not an active
fix to an active leak — stated plainly rather than implied.

**Pastor/SuperAdmin "Talk with Your Pastor" inbox** (`PastoralInboxSection`
in the new `PastoralViews.swift`) reuses `BroadcastLock` + `PasswordConfirmSheet`
exactly as instructed (this is the one place C3b deliberately copies
Broadcast's shape, since `GET /chat/pastoral/inbox` genuinely does require the
same server password step-up) — same Face-ID-releases-password fast path,
same 15-minute window, same sealed-door gate UI. **Judgment call on
placement/visibility**: it lives inside the "Talk with My Pastor" tab body
(appended below the member's own thread card) rather than as a 6th top-level
tab, and is gated on `isStaff` (SuperAdmin) — the exact same bar Broadcast
uses, on the same precedent (Broadcast's own console lives inside the Chat
screen as a role-gated segment, not a separate navigation structure). **Known
gap, stated honestly**: `PastoralService.inbox()` on the server also allows
any user who has *ever* held a `pastor_assignments` row, not just SuperAdmin
— but the route's middleware order is `requirePasswordStepUp()` BEFORE the
"not a pastor" 403 can even fire, so there is no side-effect-free way for the
client to probe "am I a pastor" to decide whether to show the entry point
without first forcing a password prompt on every member. Rather than build
that (bad UX: a password prompt just to find out a menu item shouldn't
exist), this client shows the inbox only to SuperAdmin, matching Broadcast's
existing precedent exactly, as instructed. A non-SuperAdmin pastor assigned
via `POST /admin/pastor-assignments` today has no client-side way to reach
their inbox — real, not hidden.

**Chat tab dedup**: `ChatInboxViewModel.dms` now excludes any conversation id
in `PastoralPrefs` (remembered the first time each dedicated tab resolves its
thread). Since neither `GET /chat/conversations` nor `GET
/chat/conversations/:id` return `type`, this is inherently a client-side,
session/device-taught heuristic, not a real fix — a discipler/pastoral thread
that this device has never opened through its own tab (e.g. a thread created
before this feature shipped, or opened for the first time on a second device)
will still show up as an ordinary row in the Chat tab until the member visits
"My Discipler"/"Talk with My Pastor" once. Documented rather than solved;
fixing it properly needs the backend to start sending `type`, which is out of
scope (backend untouched, per instruction).

Files: `Networking/MemberAPI+Pastoral.swift` (new — DTOs + the 4 calls),
`Features/Chat/PastoralLock.swift` (new — the lock + `PastoralPrefs`),
`Features/Chat/PastoralViews.swift` (new — `PrivateThreadCard`,
`PastoralInboxSection`), `Features/Chat/ChatView.swift` (segment enum grew
`.discipler`/`.pastor`, replaced `.group`; new tab bodies; `follow()`'s
join-request fallback), `Features/Chat/ChatThreadView.swift`
(`ChatThreadContext`, `ThreadRoute`, `pastoralMenu`, `PastoralLockedGate`),
`Auth/AuthStore.swift` (`PastoralLock.shared.reset()` on sign-out),
`Notifications/LocalNotifier.swift` (template copy above).

Verified: `xcodebuild -scheme NuruMember -configuration Debug -destination
"id=8265F608-4A98-4E95-9074-7C54BEC4684A" -derivedDataPath build/dd build` →
BUILD SUCCEEDED; `... test` → 10/10 green (first attempt hit a transient
simulator-busy `FBSOpenApplicationServiceErrorDomain` launch failure —
unrelated to this change, resolved by rerunning against the same, by-then-
idle simulator). Committed in 4 pieces on `feat/chat-four-tabs`
(`28fa934` API surface, `612eb42` four-tab restructure, `809ba9c`
`PastoralLock`, `ad70f83` thread contexts/menu/gate); this doc update is a
5th. Not pushed / no PR opened (per task instruction).

## 2026-07-20 — Selah (My Thoughts) + AI Prayer Points: Prayer Room tabs 3 & 4 (branch feat/selah-prayer-points, this repo only, client against LIVE backend pathway#391)

Prayer Room grew from three tabs (Private · Corporate · Answered) to four
(Private · Corporate · Selah · Prayer Points). Answered lost its top-level
slot but not its function — `PrayerJournalView`'s own Active/Answered chips
already show whenever it isn't force-pinned, so nothing about Answered was
removed, only relocated (no external call site passed `.answered` as an
`initialTab`, confirmed by grep before the cut).

**Selah — My Thoughts** (`SelahView.swift`, `ThoughtsViewModel`): a private
rich-text + pen journal against the now-live `/me/thoughts` REST surface,
wired through the SAME offline mutation queue as the prayer journal
(`SyncCoordinator.enqueue(domain: "member_thoughts", op: "upsert"/"delete")` —
confirmed server-side in `sync/service.ts:304-316` before wiring). One-time
explainer card (`@AppStorage("nuru.selah.explainerDismissed")`, the
`readerNight` idiom) with the owner's exact copy; empty state "Selah. Pause
here — write your first thought."; list rows show title/preview/relative time
+ a pencil glyph when a thought carries a drawing.

**The editor** (`SelahEditorView.swift` + `SelahRichEditor.swift`) is a
full-screen `UITextView` bridge (`RichTextEditor`/`RichEditorController`) —
Bold, Italic, a 6-swatch color menu, and a 4-face font menu (Inter/Fraunces/
Georgia/Noteworthy — two brand fonts + two free system fonts, deliberately
not bundling new assets) all persist PER SPAN via `ThoughtSpan{start,end,
bold?,italic?,color?,font?}`, extracted by walking the edited
`NSAttributedString`'s runs and merging adjacent identical runs (capped at
the server's 2000-span max). **Line spacing is honestly scoped as a GLOBAL
preference, not per-span** — the backend's `ThoughtSpan` has no spacing
field (confirmed reading `thoughts/service.ts`'s zod schema before building),
so a per-run line-height would silently do nothing for the rest of the note;
spacing is instead `@AppStorage("nuru.selah.lineSpacing")` applied to the
whole `UITextView`, same idiom as `readerNight`. Stated plainly rather than
silently shipping a control that doesn't actually round-trip.

**Pen drawing** (`SelahDrawingSheet.swift`) is real PencilKit (`PKCanvasView`,
`.anyInput` policy, `PKToolPicker`), gated to `UIDevice.current
.userInterfaceIdiom == .pad` — Apple Pencil doesn't exist for iPhone, so the
"Draw" toolbar entry point is hidden there rather than offering a dead end.
A drawing exports to PNG (`PKDrawing.image(from:scale:)`) and uploads through
the EXISTING `chat/attachments/sign` → Cloudinary flow
(`MemberAPI.signChatAttachment(kind: "image")` + `uploadChatAttachment`) —
confirmed the backend's `kind` enum accepts `"image"` before reusing it, no
new upload path invented. Delivered `secure_url`s append to `drawing_urls`;
removable locally before Save (no server-side cleanup of the orphaned
Cloudinary asset — same practice as every other attachment flow in this app).

**Prayer Points** (`PrayerPointsView.swift`) against the intelligence layer's
`PrayerAiService` (`intelligence/prayer.ts`, read before wiring): (a) an
assist composer — seed points → `POST /me/prayer/assist` → an editable draft
in the member's own voice, mirroring `AiDraftButton`'s visual idiom (purple→
gold orb, "Use draft"/"Discard") without reusing the component itself (the
wire shape differs — `assistantChat` summarizes a thread, `/me/prayer/assist`
takes a bare `seed`); (b) "Gather my prayer points" → `POST /me/prayer/points`
→ an editable, removable, copy-all numbered list, the corpus generator. Both
consent-gate on `ai_opt_out` — there is no separate "Sunday Letter consent
prompt" component in this codebase to reuse (checked `LetterView.swift`; the
letter itself just doesn't compose server-side when opted out), so this ships
its own gate card using the exact copy from `ProfileView`'s "Nuru
Intelligence" section, with a one-tap "Turn on AI personalization" CTA that
calls the same `MemberAPI.setAiConsent` the Profile toggle uses.

**Sync plumbing**: `member_thoughts` added to `SyncEngine.pullIdField`
(`"thought_id"`) and `SyncCoordinator.pullDomains`, matching `prayer_entries`
— confirmed `member_thoughts` is in the backend's pull-domain map
(`sync/service.ts:64`) before adding, so background delta pulls now warm the
Selah cache the same way they warm the prayer journal's.

**Honest limits**: (1) line spacing is global, not per-thought (schema
constraint, explained above); (2) drawings are add/remove-locally only — no
in-place re-editing of a saved stroke once uploaded (ships a flattened PNG,
matching the task's "clearly-scoped" fallback for anything beyond a fully-
working rich editor + real pen capture); (3) the rich editor's formatting
menus (color/font) apply to the current UITextView selection or, with an
empty selection, to `typingAttributes` going forward — full parity with how
Notes/Pages behave, no gap here.

Files: `Models/Thought.swift`, `Networking/MemberAPI+Thoughts.swift`,
`Features/Community/SelahRichEditor.swift`, `Features/Community/
SelahDrawingSheet.swift`, `Features/Community/SelahEditorView.swift`,
`Features/Community/SelahView.swift`, `Features/Community/
PrayerPointsView.swift`, `Features/Community/PrayerRoomView.swift` (tabs),
`Offline/SyncCoordinator.swift` + `Offline/OfflineStore.swift`
(`member_thoughts` pull wiring).

Verified: `xcodebuild -scheme NuruMember -configuration Debug -destination
"id=8265F608-4A98-4E95-9074-7C54BEC4684A" -derivedDataPath build/dd build` →
BUILD SUCCEEDED; `... test` → 10/10 green (simulator needed an explicit
`xcrun simctl boot` first — it was Shutdown, same transient-environment class
as the prior session's launch failure, not a code issue). Not pushed / no PR
opened (per task instruction).
