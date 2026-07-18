
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
