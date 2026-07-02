# Nuru Pathway — Backend & Database Audit

**Scope:** what the native iOS member app (`nuru-member-ios`) uses, what works, what's broken, what to add
**Date:** 2 July 2026
**Sources:** backend monorepo `pathway` (`packages/backend/src/modules/*`, OpenAPI `packages/shared/src/openapi/openapi.yaml`), iOS client `nuru-member-ios` (`NuruMember/Networking/MemberAPI.swift` + direct `APIClient` calls), live local stack (`http://localhost:8080/v1`, Postgres `nuru@localhost:5432/nuru`)
**Method:** static route extraction from all 27 backend modules; cross-reference against every API call in the iOS app; live curl of ~40 GET endpoints with a `student1@dev.local` dev token; read-only SQL row counts; code-level verification of each claimed gap. No code or data was modified.

---

## 1. Executive summary

The backend exposes roughly **300 routes**; about **190 are admin/portal routes** and about **110 are member-facing**. The iOS app wires **~85 of the member-facing routes** through `MemberAPI.swift` (plus auth/refresh in `APIClient`/`AuthStore`, sync in `OfflineStore`, and a handful of direct calls in `ProfileView`/`GivingView`). Live verification against the local stack shows the wired surface is in **very good health**: home dashboard, pathway/modules/quizzes, growth (devotional, memory verses, plans, resources, mentor), prayer journal & wall, chat inbox/send, calendar/events/RSVP, giving history/intents/schedules, gifts assessment, badges, notifications, and offline sync all return correct, well-shaped data.

The problems cluster in four places:

1. **Dangling contracts** — `GET /certificates` returns a `download_url` of `/media/certificates/{code}` that **no route serves** (confirmed 404); the chat conversation list omits the DM peer's `user_id`, forcing the iOS mentor screen into a name-matching hack.
2. **Backend-ready, iOS-unwired** — space join (`POST /chat/spaces/:id/join`), DM creation (`POST /chat/dms`), QR event check-in (`POST /events/:id/attendance`), event posts/"buzz" (`GET/POST /events/:id/posts`), avatar upload, push-token registration (`POST /me/devices`), per-pillar score details, level exams, community threads, share-prayer-to-wall — all exist and are documented in OpenAPI but the app never calls them.
3. **Provider keys absent** — assistant (`GROQ_API_KEY`/`GEMINI_API_KEY`) and scripture (`YOUVERSION_APP_KEY`) return `UPSTREAM_UNAVAILABLE` locally; both must be configured in prod.
4. **Genuinely missing** — a member notification-preferences endpoint (prefs are written once at onboarding, and the iOS onboarding flow doesn't exist, so `notification_preferences` has **0 rows**); a live-stream/radio source for the Home "Radio" button and LiveNow card; a plan-day reflection endpoint; a PayPal capture call in the iOS flow (opens the approval URL but never calls `POST /giving/paypal/capture`, so PayPal gifts can never settle from the app).

---

## 2. Member-facing route inventory

Legend — **WIRED**: called from the iOS app (`MemberAPI.swift` or direct `APIClient` call). **UNUSED**: route exists, app never calls it. **MISSING**: the app/design needs it and no route exists (listed in §2.15). Admin/portal routes (`/admin/*`, leader-only engagement/assessment-review routes) are out of scope and counted only in the appendix.

### 2.1 Identity & auth (`modules/identity`)

| Method | Path | Purpose | Status |
|---|---|---|---|
| POST | /auth/login | Email+password login (may return 2FA challenge) | WIRED |
| POST | /auth/login/mfa | Complete a 2FA login challenge | WIRED |
| POST | /auth/register | Create an account and sign in | WIRED |
| POST | /auth/token/refresh | Rotate the refresh token | WIRED |
| POST | /auth/password/forgot | Request reset (dev returns `dev_token`) | WIRED |
| POST | /auth/password/reset | Set new password from token | WIRED |
| POST | /auth/mfa/enroll | Begin TOTP enrollment | WIRED |
| POST | /auth/mfa/verify | Confirm enrollment code | WIRED |
| POST | /auth/mfa/disable | Turn off 2FA | WIRED |
| POST | /auth/logout | Revoke the session server-side | UNUSED |
| POST | /auth/oauth/:provider | KingsChat/OIDC social login | UNUSED |
| POST | /auth/dev-login | Dev-only instant login | N/A (dev) |
| GET | /me | Profile + enrollment summary | WIRED |
| PATCH | /me | Update profile fields | WIRED |
| POST | /me/password | Change password | WIRED |
| GET | /me/activity | Member's own audit/activity feed | UNUSED |
| POST | /me/devices | Register a push token (APNs/FCM) | UNUSED |
| POST | /me/onboarding | Legacy onboarding marker | UNUSED |

### 2.2 Home dashboard (`modules/home`, plus member routes in `adminops`)

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /me/home/greeting | Warm daily greeting line | WIRED |
| GET | /me/home/next-action | Next-best-action hero card | WIRED |
| GET | /me/home/verse | Tailored verse for today | WIRED |
| GET | /me/home/verse/reactions | Community reaction counts | WIRED |
| POST | /me/home/verse/reactions | Set my reaction | WIRED |
| GET | /me/rhythm/today | Today's three daily rhythms | WIRED |
| POST | /me/rhythm/complete | Mark a rhythm done (idempotent) | WIRED |
| GET | /home/featured-cell | "This week at Nuru" cell card | WIRED |

### 2.3 Curriculum & pathway (`modules/curriculum`, `progress`, `assessment`)

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /me/pathway | Level trail with progress + status | WIRED |
| GET | /levels | Level catalogue | UNUSED |
| GET | /levels/:n/modules | Module trail for a level | WIRED |
| GET | /modules/:id | Full lesson (server-gated, §1.9) | WIRED |
| GET | /scripture?ref= | Passage text (YouVersion-backed) | WIRED |
| POST | /modules/:id/complete | Finish a non-quiz module (+reflection) | WIRED |
| GET | /modules/:id/quiz | Server-assembled quiz | WIRED |
| POST | /modules/:id/quiz/attempts | Submit answers, scored server-side | WIRED |
| GET | /modules/:id/reflection | My reflection + review status | UNUSED |
| GET | /levels/:n/exam | Level exam paper | UNUSED |
| POST | /levels/:n/exam/attempts | Submit level exam | UNUSED |
| POST | /levels/:n/reflection | Level-gate reflection submission | UNUSED |
| POST | /events/:id/attendance | **QR/manual event check-in (member)** | UNUSED |

### 2.4 Growth content (`modules/growth-content`)

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /growth/devotional | Today's devotional (+my reflection) | WIRED |
| POST | /growth/devotional/reflection | Save reflection; marks rhythm | WIRED |
| GET | /growth/memory-verses | Memory-verse set with status | WIRED |
| POST | /growth/memory-verses/practice | Log a practice attempt | WIRED |
| GET | /growth/plans | Reading-plan catalogue | WIRED |
| GET | /growth/plans/:id | Plan with day-by-day breakdown | WIRED |
| POST | /growth/plans/:id/start | Enrol in a plan | WIRED |
| POST | /growth/plans/:id/complete-day | Mark a whole day done | WIRED |
| POST | /growth/segments/:id/complete | Mark one plan-day segment done | WIRED |
| GET | /growth/resources | Library (books/audio/video/articles) | WIRED |
| GET | /growth/mentor | Assigned discipler + meeting notes | WIRED |
| GET | /home/disciplers | "Meet your discipler" carousel | WIRED |

### 2.5 Personal growth data (`modules/growth`)

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /me/prayers | Private prayer journal | WIRED |
| PUT | /me/prayers | Upsert entry (idempotent) | WIRED |
| DELETE | /me/prayers/:id | Delete entry | WIRED |
| GET | /me/verses | Saved-verse library | WIRED |
| PUT | /me/verses | Save/update a verse | WIRED |
| DELETE | /me/verses/:id | Remove a saved verse | WIRED |
| GET | /me/gifts | Spiritual-gifts profile | WIRED |
| GET | /gifts/questions | Likert question set | WIRED |
| POST | /gifts/assessments | Submit answers → new profile | WIRED |

### 2.6 Scores (`modules/scores`)

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /me/scores | Five growth scores + weighted overall | WIRED |
| GET | /me/scores/habits | Habits pillar detail | UNUSED |
| GET | /me/scores/curriculum | Curriculum pillar detail | UNUSED |
| GET | /me/scores/attendance | Attendance pillar detail | UNUSED |
| GET | /me/scores/prayer | Prayer pillar detail | UNUSED |
| GET | /me/scores/word | Word pillar detail | UNUSED |

### 2.7 Calendar, events & moments (`modules/calendar`)

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /calendar?from=&to= | Occurrences in a date window | WIRED |
| GET | /calendar/series | Followable event series | WIRED |
| POST | /calendar/series/:id/follow | Toggle following a series | WIRED |
| GET | /home/featured-event | Admin-featured event | WIRED |
| GET | /events/:id | Full event detail (occurrence id) | WIRED |
| POST | /events/:id/rsvp | Set RSVP | WIRED |
| GET | /me/rsvps | My RSVPs | WIRED |
| GET | /me/cell-summary | My cell card | WIRED |
| GET | /moments | Curated photo gallery | WIRED |
| GET | /events/:id/posts | **Event buzz/posts feed** | UNUSED |
| POST | /events/:id/posts | Post to an event's buzz | UNUSED |
| POST | /events/:id/posts/:postId/react | React to a buzz post | UNUSED |
| POST | /calendar/parse | Natural-language event parse | UNUSED |

### 2.8 Announcements (`modules/announcements`)

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /home/featured-announcement | Admin-featured announcement | WIRED |
| GET | /me/announcements | My announcements | WIRED |
| GET | /announcements/:id | Full announcement (carousel + body) | WIRED |
| POST | /announcements/:id/open | Mark opened (best-effort) | WIRED |

### 2.9 Giving & products (`modules/financial`) — online-only, §5.6

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /giving/history | Gift history | WIRED |
| POST | /giving/intents | Create a gift intent (M-Pesa/Airtel/PayPal) | WIRED |
| GET | /giving/transactions/:id | Gift detail incl. ledger trail | WIRED |
| GET | /giving/schedules | Recurring gifts | WIRED |
| POST | /giving/schedules | Create a recurring gift | WIRED |
| POST | /giving/schedules/:id/cancel | Cancel a schedule | WIRED |
| POST | /giving/paypal/capture | **Capture an approved PayPal order** | UNUSED ⚠ (breaks PayPal settle — see §4.6) |
| GET | /giving/statement.pdf | Annual statement PDF | UNUSED (statement screen renders natively) |
| GET | /giving/transactions/:id/receipt.pdf | Receipt PDF | UNUSED |
| GET | /products | Purchasable products | UNUSED (0 rows) |
| POST | /products/:id/purchase | Buy a product | UNUSED |

### 2.10 Chat (`modules/chat`)

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /chat/conversations?scope=mine | Inbox (Spaces/DMs/Groups + `discover_spaces`) | WIRED |
| GET | /chat/conversations/:id | Thread with messages | WIRED |
| POST | /chat/conversations/:id/messages | Send a message (idempotent) | WIRED |
| POST | /chat/conversations/:id/read | Mark thread read | WIRED |
| POST | /chat/messages/:id/reactions | Toggle emoji reaction | WIRED |
| POST | /chat/spaces/:id/join | **Join a public space** | UNUSED ⚠ (backend ready; iOS "Browse spaces" is a dead button) |
| POST | /chat/dms | **Create/get a DM by user_id** | UNUSED ⚠ (would fix the mentor name-hack) |
| GET | /chat/people | People directory for new DMs | UNUSED |
| POST | /chat/attachments/sign | Cloudinary signed-upload for attachments | UNUSED |
| PATCH / DELETE | /chat/messages/:id | Edit / delete own message | UNUSED |
| GET | /chat/messages/:id/readers | Read receipts | UNUSED |
| POST | /chat/messages/:id/flag · /unflag | Report a message | UNUSED |
| POST | /chat/cells/:id/conversation, /chat/spaces | Leader-only creation | N/A (leader) |

### 2.11 Prayer wall & community (`modules/prayer-wall`, `community`)

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /prayer-wall?sort= | Shared prayer requests | WIRED |
| GET | /prayer-wall/:id | One request + comments | WIRED |
| POST | /prayer-wall | Share a request | WIRED |
| POST | /prayer-wall/:id/reactions | Toggle 🙏 etc. | WIRED |
| POST | /prayer-wall/:id/comments | Encourage the requester | WIRED |
| POST | /prayer-wall/:id/answered | Author marks (un)answered | WIRED |
| DELETE | /prayer-wall/:id | Author removes request | WIRED |
| GET | /home/prayer-wall | Home carousel posts | WIRED |
| POST | /me/prayers/:id/share-to-wall | **Promote a journal entry to the wall** | UNUSED |
| GET/POST | /community/threads, /:id, /:id/comments | Cell discussion board | UNUSED (0 rows; iOS Community tab shows it as "coming soon") |

### 2.12 Gamification, certificates, encouragements

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /me/achievements | Badges + streak | WIRED |
| GET | /badges | Badge catalogue | WIRED |
| GET | /members/:id/achievements | Another member's badges | UNUSED |
| GET | /cells/:id/milestones | Cell milestones | UNUSED |
| GET | /certificates | My certificates (with `download_url`) | WIRED |
| GET | /verify/:code | Public certificate verification | WIRED |
| GET | /levels/:n/encouragements | Level-gate encouragement messages | UNUSED (0 rows) |

### 2.13 Notifications, media, assistant, proximity, sync, activity

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /me/notifications | Notification center + unread count | WIRED |
| POST | /me/notifications/read | Mark some/all read | WIRED |
| GET | /home/welcome-video | Homepage welcome video | WIRED |
| POST | /media/:id/reactions | Toggle media reaction | WIRED |
| POST | /me/avatar | Upload profile photo | UNUSED |
| GET | /media/:id/manifest, /media/url | Video manifest / URL broker | UNUSED |
| GET | /assistant/history | Prior assistant turns | WIRED |
| POST | /assistant/chat | Nuru AI companion reply | WIRED (needs provider key) |
| POST | /me/location | Share coarse geohash | WIRED |
| DELETE | /me/location | Opt out of location | WIRED |
| POST | /sync/push | Replay offline mutation queue | WIRED |
| POST | /sync/pull | Cursor-driven delta pull | WIRED |
| POST | /me/activity/screens | Screen-view analytics batch | UNUSED (0 rows) |

### 2.14 Onboarding (`modules/onboarding`) — entire module unwired

| Method | Path | Purpose | Status |
|---|---|---|---|
| GET | /onboarding | Step-machine state | UNUSED |
| PUT | /onboarding/steps/{profile,cell_selection,literacy_quiz,notifications,guardian_consent} | Save each step | UNUSED |
| GET | /onboarding/literacy-quiz | Literacy quiz paper | UNUSED |
| POST | /onboarding/finalize | Complete onboarding | UNUSED |
| GET | /directory/cell-groups | Cell picker directory | UNUSED |

The native app registers via `POST /auth/register` and lands straight on Home; the onboarding flow (and with it the **only** write path to `notification_preferences`) is never exercised.

### 2.15 MISSING — no route exists

| Needed by | What's missing |
|---|---|
| Certificates screen | `GET /media/certificates/:code` — the URL every certificate's `download_url` points at (`certificates/service.ts:99`). Confirmed live: returns an Express plain-404 (route absent). PDFs *are* rendered and stored in the ObjectStore at issuance; they just cannot be fetched. |
| Profile → notification toggles | Member `GET/PUT /me/notification-preferences`. The three iOS toggles are `@AppStorage` local-only (`ProfileView.swift:20-22`); the server table is written only by the unused onboarding step. `notification_preferences`: **0 rows**. |
| Home "Radio" button + LiveNow card | Any live-stream source. Zero matches for `radio|stream_url|livestream` across all backend modules. The LiveNow card is driven purely by calendar occurrence timing; tapping "Radio" just opens the occurrence — there is nothing to play. |
| Reading-plan day screen | Plan-day reflection endpoint (e.g. `POST /growth/plans/:id/days/:n/reflection`). iOS comment confirms: *"no reflection binding for plan days"* (`ReadingPlansView.swift:641-642`). |
| Mentor "Message" button | `peer_user_id` on each DM row in `GET /chat/conversations`. The SQL joins the peer (`od.user_id`) but only selects their name/avatar (`chat/service.ts:282-305`), so `MentorView.swift:17-28` matches the mentor's DM **by full name**. (Alternative fix needing no contract change: iOS calls `POST /chat/dms` with `mentor_user_id`, which `GET /growth/mentor` already returns.) |

---

## 3. Live verification — what works, what doesn't

### 3.1 Endpoint spot-checks (dev token, `student1@dev.local`)

| Endpoint | Result |
|---|---|
| GET /me | ✅ Full profile (Ada Thriving, Student, cell + congregation ids) |
| GET /me/pathway | ✅ 6 levels, level 1 active 20/30 modules |
| GET /me/rhythm/today | ✅ `{prayer:false, word:false, reflection:false}` |
| GET /me/home/next-action | ✅ "Continue: God & His Nature" resume card |
| GET /me/home/greeting · /verse · /verse/reactions | ✅ All populated (verse from `daily_verses`, 365 rows seeded) |
| GET /me/scores (+ /me/scores/word etc.) | ✅ Overall 22 with all five pillars + component detail |
| GET /me/achievements | ✅ Shape correct; empty badges/streak (no `user_badges`/`user_streaks` rows) |
| GET /me/notifications | ✅ Works; empty (`notifications`: 0 rows — nothing has ever fanned out) |
| GET /growth/devotional · memory-verses · plans · resources · mentor | ✅ All richly seeded (7 plans, 54 memory verses, 2 devotionals, 5 resources, mentor + 3 notes) |
| GET /home/featured-event · -announcement · -cell · welcome-video · disciplers · prayer-wall · /moments | ✅ All populated |
| GET /calendar · /calendar/series | ✅ Occurrences and 5 series |
| GET /events/{occurrence-id} | ✅ Works **with occurrence-style ids** (`seriesId:ISO-timestamp`); plain series ids 404 as expected |
| GET /events/{id}/posts | ✅ Route works; returns `{"data":[]}` (`event_posts`: 0 rows) |
| GET /chat/conversations?scope=mine | ✅ 1 cell group conversation + `discover_spaces` array present |
| GET /prayer-wall | ✅ 5 posts |
| GET /giving/history · /schedules · statement.pdf | ✅ 7 transactions, valid PDF streamed |
| GET /me/prayers · /me/verses | ✅ Seeded incl. rows written via offline queue |
| GET /gifts/questions · /me/gifts | ✅ Question set served; profile empty (no assessments yet) |
| GET /certificates | ✅ Route fine but empty (`certificates`: 0 rows) — and see broken `download_url` §4.1 |
| GET /badges | ✅ 6 badge definitions |
| GET /levels/1/modules vs /levels/3/modules | ✅ Level 1 full; level 3 returns `[]` (no published modules above level 2 — 71 modules total, seeded through level 2) |
| GET /levels/1/encouragements | ⚠ Empty — table has **0 rows**; nobody has authored encouragements |
| GET /community/threads | ⚠ Empty — feature dark on both ends |
| GET /scripture?ref=John 3:16 | ❌ `UPSTREAM_UNAVAILABLE — "Scripture is not configured"` (`YOUVERSION_APP_KEY` unset; `scripture.ts:55`) |
| POST /assistant/chat | ❌ (verified via code, not curled — it writes history) Same pattern: provider selected only if `GROQ_API_KEY` or `GEMINI_API_KEY` set (`assistant/provider.ts:155-156`); otherwise `UPSTREAM_UNAVAILABLE`. `assistant_messages`: 0 rows. |
| GET /media/certificates/SOMECODE | ❌ Plain Express 404 — **route does not exist** |

### 3.2 Database health (row counts, local dev DB)

**Populated (healthy):** `users` 10 · `levels` 6 · `modules` 71 · `module_progress` 51 · `attendance_logs` 23 · `event_series` 5 · `events` 9 · `event_moments` 6 · `memory_verses` 54 · `reading_plans` 7 · `devotionals` 2 · `daily_verses` 365 · `prayer_wall_posts` 5 · `prayer_entries` 2 · `saved_verses` 1 · `transactions` 7 · `ledger_entries` 12 · `announcements` 3 · `badges` 6 · `resources` 5 · `mentor_notes` 3 · `gift_question_sets` 1 · `chat_conversations`/`chat_messages` 1/1 · `media_assets` 1 · `member_location` 1 · `verse_reactions` 1.

**Empty (features never exercised or never fed):**

| Table | Why it's empty | Signal |
|---|---|---|
| `notification_preferences` | Only write path is the unwired onboarding step | Prefs feature effectively dead |
| `notifications`, `notification_states`, `push_tokens` | No fan-out has run; iOS never registers a push token | No push pipeline end-to-end |
| `event_posts`, `event_post_reactions` | Buzz routes exist, no client posts | Feature dark |
| `event_rsvps`, `event_guests` | No RSVPs made yet (route works) | Data-only |
| `discussion_threads`, `discussion_comments` | Community threads unwired in iOS | Feature dark |
| `certificates` | No member has passed a level exam (exams also unwired in iOS) | Blocked chain: exam → cert → download |
| `user_badges`, `user_streaks`, `gamification_events` | No awards triggered yet | Data-only |
| `assistant_messages` | Assistant blocked on provider key locally | Config |
| `level_encouragements` | No admin has authored any | Content gap |
| `devotional_reflections`, `reading_plan_progress`, `quiz_attempts`, `gift_assessments`, `video_progress`, `app_screen_events`, `giving_schedules`, `products`, `prayer_wall_comments` | Awaiting normal usage / seeding | Data-only |

---

## 4. Known gaps — verified against code

Each claim from the brief was checked against source; two turn out to be *client-side* gaps rather than missing backend routes.

### 4.1 Certificate `download_url` → CONFIRMED backend bug
`certificates/service.ts:99` emits `download_url: /media/certificates/{verification_code}` for every certificate. No module registers that route (grepped all 27; live request 404s at the Express layer). The PDF **is** rendered at issuance (`service.ts:75-81`) into the ObjectStore (`certificates/{code}.pdf`) — in dev an `InMemoryObjectStore`, so a real deployment also needs the S3/Cloudinary implementation dropped in. **Fix: add the serving route (auth or signed) + a persistent ObjectStore in prod.**

### 4.2 Chat space join → CORRECTED: backend route EXISTS; iOS is unwired
`POST /chat/spaces/:id/join` exists (`chat/index.ts:110`) and `discover_spaces` is returned by the inbox and decoded by the iOS model (`Models/Chat.swift:36,73`). But the iOS "Browse spaces" compose action (`ChatView.swift:459`) has no destination and no join call anywhere in the app. **Fix is iOS-only.**

### 4.3 Notification preferences → CONFIRMED (both sides)
No member route reads/writes `notification_preferences`; the only writer is `PUT /onboarding/steps/notifications`, and iOS has no onboarding flow. iOS toggles are `@AppStorage`-local (`ProfileView.swift:20-22, 374-376`). Table: 0 rows. **Fix: add `GET/PUT /me/notification-preferences` + wire the toggles.** Related: `POST /me/devices` (push-token registration) exists but iOS never calls it, and `push_tokens` is empty — even with prefs, no push can be delivered.

### 4.4 Event check-in / QR → CORRECTED: member route EXISTS; iOS is unwired
`POST /events/:id/attendance` (progress module, `index.ts:43-52`) validates a scan token, is idempotent, and is also replayable offline via `sync/push` (`attendance:scan` mutation kind). Admin-side manual check-in also exists (`POST /admin/events/:id/checkins`). The iOS app has no scanner or check-in call. **Fix is iOS-only** (QR scanner screen + call, or offline enqueue).

### 4.5 Event posts / buzz → CONFIRMED: routes exist, unused
`GET/POST /events/:id/posts` and `POST /events/:id/posts/:postId/react` all exist and respond correctly live (`{"data":[]}`; `event_posts` 0 rows). Documented in OpenAPI. Ready for the iOS wiring reportedly in flight.

### 4.6 PayPal capture → NEW FINDING: iOS flow cannot settle PayPal gifts
`GivingView.swift:722-780`: the app creates the intent, opens `approve_url`, then polls `GET /giving/transactions/:id` for up to ~60 s. It **never calls `POST /giving/paypal/capture`** (`financial/index.ts:39-47`), which is what settles the ledger after approval. Unless a return-URL/webhook path captures server-side, every PayPal gift stalls in `processing`. **Fix: call capture on return-to-app (universal link or poll-then-capture).**

### 4.7 Per-pillar score details → CONFIRMED unused
All five `GET /me/scores/{pillar}` detail endpoints work (curled `word`, `habits`) with component/detail breakdowns; iOS only calls the summary. Opportunity: a "Why is my score X?" drill-down screen at near-zero backend cost.

### 4.8 `levels/:n/encouragements` → CONFIRMED unused + no content
Route works, iOS never calls it, and `level_encouragements` has 0 rows. Two gaps: wiring and authoring.

### 4.9 Community threads → CONFIRMED dark on both ends
Routes work; iOS Community tab lists "Cohort Discussions" as a dead (`live: false`) row (`CommunityView.swift:23-24`). Sync already supports `discussion_threads:create` / `discussion_comments:create` offline mutations, and pull domains include both tables — the plumbing is fully built.

### 4.10 Prayer share-to-wall → CONFIRMED unused
`POST /me/prayers/:id/share-to-wall` exists (prayer-wall module); no iOS call. The journal entry sheet has no "Share to wall" action.

### 4.11 Assistant provider key → CONFIRMED
`buildProvider` (`assistant/provider.ts:155-156`): Groq preferred, Gemini fallback, else every chat throws `UPSTREAM_UNAVAILABLE`. Both `GROQ_API_KEY` and `GEMINI_API_KEY` are optional in `config/env.ts:79-82`. Same class of issue as scripture (`YOUVERSION_APP_KEY`, confirmed failing live). **Set both keys in prod or the Nuru companion and in-app Bible text are dead.**

### 4.12 Live-stream / radio → CONFIRMED absent
No route, column, or env var relating to streaming anywhere in the backend. Home's Radio button and LiveNow card (`HomeView.swift:284-390`) navigate to a calendar occurrence — honest, but there is nothing to listen to.

### 4.13 Plan-day reflection → CONFIRMED absent
Growth-content module has only the devotional reflection endpoint. No per-plan-day reflection route; iOS explicitly omitted the mock's reflection textarea for this reason.

### 4.14 Mentor peer-user-id → CONFIRMED contract gap
Detailed in §2.15. The data exists on both sides; only the conversation-list contract hides it.

---

## 5. Recommendations — prioritized roadmap

Effort: S ≈ ≤half-day · M ≈ 1–2 days · L ≈ 3+ days, per surface.

### P1 — broken promises & prod blockers

| # | Feature | Backend work | iOS work | DB work | Why it matters | Effort |
|---|---|---|---|---|---|---|
| 1 | Certificate download | Add `GET /media/certificates/:code` streaming from ObjectStore (auth: owner or valid code); wire S3/Cloudinary ObjectStore in prod | Add "Download PDF" button using existing `downloadUrl` | none (PDF keys already stored) | The app already shows the URL; a graduate's certificate is the pathway's crowning artifact and today it 404s | B:S · iOS:S |
| 2 | PayPal settle | (Optional) also capture server-side on PayPal webhook | Call `POST /giving/paypal/capture` on return-to-app; deep-link return URL | none | Money path is silently broken — gifts stall in `processing`, eroding trust in giving | B:S · iOS:M |
| 3 | Assistant + scripture keys in prod | Set `GROQ_API_KEY` (or `GEMINI_API_KEY`) and `YOUVERSION_APP_KEY` on the VPS; add readiness check/log warning when absent | none | none | Two flagship features (Nuru companion, in-app Bible text) hard-fail without them | B:S |
| 4 | Notification preferences + push registration | `GET/PUT /me/notification-preferences` (upsert; reuse onboarding step logic); OpenAPI | Bind the three Profile toggles to the API; call `POST /me/devices` with the APNs token after permission grant | none (table exists) | Server can't respect member choices it never receives; `push_tokens` empty means **zero** push reach today | B:S · iOS:M |
| 5 | Space join + mentor DM | Add `peer_user_id` to DM rows in `listConversations` (one SELECT column); OpenAPI | Browse-spaces sheet (list `discover_spaces` → `POST /chat/spaces/:id/join`); mentor Message button → `POST /chat/dms` with `mentor_user_id` | none | Chat discovery is a dead button; mentor messaging rests on a name-collision-prone hack | B:S · iOS:M |

### P2 — high-value wiring of ready backend

| # | Feature | Backend work | iOS work | DB work | Why it matters | Effort |
|---|---|---|---|---|---|---|
| 6 | Event buzz (posts) | none — routes live | Posts feed + composer + reactions on event detail (reportedly in flight) | seed demo posts | Turns events from listings into community moments | iOS:M |
| 7 | QR event check-in | none — route + offline `attendance:scan` ready | Scanner screen; enqueue offline | none | Attendance feeds the attendance score pillar; members currently can't check in at all | iOS:M |
| 8 | Level exams + encouragements | none (routes ready); author `level_encouragements` content | Exam screen (`GET /levels/:n/exam`, submit attempts); show encouragements at level gates | seed encouragements | Level progression — the core pathway loop — cannot complete in the native app today; certificates depend on it | iOS:L · content:S |
| 9 | Score drill-downs | none — five detail endpoints live | "Why this score?" sheet per pillar using components/detail | none | Makes growth scores explainable and actionable instead of a bare number | iOS:M |
| 10 | Community threads | none — routes + offline sync ready | Cohort Discussions screen (list/create/comment) | seed a starter thread per cell | The Community tab advertises it; cell-level belonging is the retention engine | iOS:L |
| 11 | Notifications fan-out | Verify outbox → `notifications` fan-out jobs run in prod (table empty even for in-app rows); wire `PUSH_PROVIDER_KEY` | none beyond #4 | none | Notification center is an empty room until something writes to it | B:M |

### P3 — new product surface

| # | Feature | Backend work | iOS work | DB work | Why it matters | Effort |
|---|---|---|---|---|---|---|
| 12 | Live stream / radio | `GET /live` (or `stream_url` + `is_live` on occurrences/series); admin CRUD for stream config | Player sheet behind the Radio button + LiveNow CTA | `live_streams` table or columns on `event_series` | The Home UI already promises it; live services are the strongest weekly touchpoint for remote members | B:M · iOS:M · DB:S |
| 13 | Plan-day reflection | `POST /growth/plans/:id/days/:n/reflection` (+ GET with day payload); count toward reflection rhythm | Reflection textarea on the plan-day screen | `reading_plan_day_reflections` table | Reflection is one of the three daily rhythms; plans are where members read most | B:M · iOS:S · DB:S |
| 14 | Share prayer to wall | none — route exists | "Share to wall" action on journal entries | none | Bridges private discipline to communal encouragement in one tap | iOS:S |
| 15 | Avatar upload + logout | none — `POST /me/avatar`, `POST /auth/logout` exist | Photo picker on the profile pencil; call logout on sign-out | none | Identity/personal presence in chat, wall, disciplers; clean session hygiene | iOS:S |
| 16 | Chat depth (attachments, edit/delete, receipts, flag) | none — all routes exist | Attachment picker via `chat/attachments/sign`; long-press actions | none | Brings native chat to parity with the web portal and member expectations | iOS:L |
| 17 | Screen analytics | none — `POST /me/activity/screens` exists | Batch screen events from the router | none | `app_screen_events` is empty; engagement scoring and the admin Intelligence grid are flying blind on native usage | iOS:S |

---

## 6. Appendix

### 6.1 Surface counts
- Backend routes total (all modules): ~300 (258 paths documented in OpenAPI — coverage spot-checks all passed, including the unused buzz and join routes)
- Admin/portal-only routes: ~190 across `adminops`, `system`, `curriculum` admin, `financial` admin, `media` admin, `announcements` admin, `growth-content` admin, `certificates` admin, `gamification` admin, `proximity` admin, `encouragements` admin, `community` moderation, `assessment` review, `engagement` (leader), `calendar` admin
- Member-facing routes: ~110 · wired from iOS: ~85 · unused: ~25 · missing: 5 (§2.15)

### 6.2 Offline sync contract (working)
- Push mutation kinds accepted: `module_progress:complete`, `quiz_attempts:submit`, `level_exam_attempts:submit`, `interaction_events:record`, `video_progress:update`, `event_rsvps:set`, `attendance:scan`, `prayer_entries:upsert/delete`, `saved_verses:save/delete`, `discussion_threads:create`, `discussion_comments:create`, `chat_messages:create`, `chat_reactions:toggle`, `chat_reads:set`, `gift_assessments:submit`. Money domains are rejected at the source on both client and server (§5.6).
- Pull domains mirrored in `OfflineStore.pullIdField` match the backend's `PULL_DOMAINS`; delta pull with tombstones verified working live (prayer/verse rows written via the queue appear in reads).

### 6.3 Notable environmental facts
- Dev login (`POST /auth/dev-login`) available; local stack healthy (`/healthz`, `/readyz` ok).
- Event detail ids are **occurrence ids** (`seriesId:ISO-start`) — the featured-event `series_id` alone will 404 on `GET /events/:id`; clients must pass the occurrence id (the iOS calendar path does this correctly).
- Levels 3–6 have no published modules yet (71 modules cover levels 1–2); `GET /levels/3/modules` correctly returns an empty list rather than leaking content (hard-lock §1.9 intact).

*End of audit.*
