
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
