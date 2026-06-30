# Nuru Place member app — React Native → native iOS Swift migration

**Decision (2026-06-30):** the member app's iOS surface moves off React Native to
a **native SwiftUI app in this standalone repo** (`nuru-member-ios`). This is
**step one of retiring React Native entirely** — once iOS is native and at parity,
Android moves to native Kotlin (or is paused) and `packages/mobile` is retired.

This is the native counterpart of the **iPad admin portal** (`iphone/ios-native/
NuruPortal`), which already proved the pattern (URLSession actor client, Keychain
token vault, SwiftUI feature views over the same prod backend). The member app
reuses that architecture and the shared design tokens.

---

## 1. Why / what stays fixed

The **backend + OpenAPI contract is the source of truth** and does **not** change.
Same API surface (`https://pathway.nuruplace.org/v1`), same auth (§5.3), same
offline sync protocol (§1.7, §3.6), same gating invariant (§1.9), same money rules
(§5.6). This is a **client rewrite only** — every server guarantee is preserved.

What we are replacing: the RN/TypeScript client in `packages/mobile/src` (~22k LOC,
37 screens, Redux, axios, react-native-keychain, op-sqlite offline store).

What we keep faithful:
- **Design language** — ported 1:1 from `packages/mobile/src/theme/tokens.ts` into
  `Theme/NuruTheme.swift` (warm paper, navy/gold, Inter + Fraunces, one soft shadow).
- **Offline-first** — the pending-mutations queue stays the system of record; the
  UI reads a local cache; money is never queued (§5.6).
- **Auth** — access/refresh pair in the Keychain; single-flight refresh on 401.

---

## 2. Architecture mapping (RN → Swift)

| React Native (`packages/mobile/src`) | Native iOS (`NuruMember/`) | Status |
|---|---|---|
| `theme/tokens.ts`, `theme/components.tsx` | `Theme/NuruTheme.swift`, `Features/Shared/Components.swift` | ✅ ported |
| `api/client.ts` (axios + interceptors) | `Networking/APIClient.swift` (URLSession actor) | ✅ ported |
| `api/client.ts` `NuruApi.*` methods | `Networking/MemberAPI.swift` | ◑ slice only |
| `auth/keychainTokenVault.ts` | `Auth/KeychainStore.swift` | ✅ ported |
| `auth/session.ts` (refresh-once) | `APIClient.refreshSession` (single-flight) | ✅ ported |
| `store/*` (Redux Toolkit) | `@StateObject` view models + `AuthStore` | ◑ per-screen |
| `sync/syncEngine.ts`, `sync/offlineWrite.ts` | `Offline/OfflineStore.swift` (`SyncEngine`) | ◑ skeleton |
| `db/localStore.ts` + op-sqlite | `Offline/FileLocalStore` → SQLCipher (later) | ◑ skeleton |
| `navigation/RootNavigator.tsx` | `Features/Shell/RootView.swift` (TabView + NavigationStack) | ◑ shell |
| `screens/*.tsx` (37) | `Features/<Area>/*.swift` | ◑ 2 of 37 |
| `config.ts` (base URL) | `APIClient.resolveBaseURL()` | ✅ ported |

`✅ done · ◑ in progress · ☐ not started`

State management: we deliberately **do not** port Redux. SwiftUI's
`@StateObject`/`@Published` view models per screen + a single `AuthStore`
environment object cover what the RN app used Redux for (session + offline slice).
The offline slice becomes the on-disk `LocalStore`.

---

## 3. Screen inventory (37 RN screens → port phases)

Grouped by tab area. Each becomes a SwiftUI view + view model calling `MemberAPI`.

**Phase 0 — vertical slice (DONE this session):**
- `LoginScreen` → `Features/Login/LoginView.swift` (+ 2FA step)
- `HomeDashboardScreen` → `Features/Home/HomeView.swift` (/me, next-action, rhythm)
- Tab shell + `ProfileScreen` (minimal) → `Features/Shell/RootView.swift`

**Phase 1 — Pathway (the §1.9 hard-lock core):**
LevelsScreen, LevelScreen, ModuleScreen, QuizScreen, ReflectionScreen,
LevelCompleteScreen. Gating is server-enforced; the client must never show
higher-level content than `current_level`.

**Phase 2 — Daily rhythm & Word:**
DevotionalScreen, MemoryVerseScreen, ReadingPlansScreen, PlanDetailScreen,
PlanDayScreen, VerseLibraryScreen, PrayerJournalScreen.

**Phase 3 — Community:**
ChatScreen, ChatThreadScreen, NewMessageScreen, ThreadScreen,
CohortDiscussionsScreen, PrayerWallScreen, PrayerWallDetailScreen, SpacePreviewScreen.

**Phase 4 — Events & Calendar:**
EventsScreen, EventDetailScreen, CalendarScreen, AnnouncementDetailScreen,
NotificationsScreen.

**Phase 5 — Giving (online-only, §5.6 — Stripe via `SFSafariViewController`/Elements):**
GivingScreen, GivingReceiptScreen, GivingStatementScreen.

**Phase 6 — Profile & growth:**
ProfileScreen (full), GiftsScreen, MentorScreen, WatchScreen,
ResourcesLibraryScreen, NuruAssistantScreen.

---

## 4. Offline sync port (the hard part)

The RN app's offline engine (`sync/syncEngine.ts` + op-sqlite SQLCipher store) is
the riskiest port. Strategy:

1. **Contract first (DONE):** `Offline/OfflineStore.swift` defines `PendingMutation`,
   the `LocalStore` protocol, a `FileLocalStore`, and a `SyncEngine` with
   `enqueue` / `push` / `pull`. The money guard (§5.6) and monotonic per-device
   `seq` are in place. `writeThrough` semantics (online-first, degrade to queue on
   network error only) move into a small helper alongside this.
2. **Storage upgrade:** swap `FileLocalStore` for an SQLCipher-backed store
   (GRDB + SQLCipher) behind the same `LocalStore` protocol — parity with op-sqlite,
   encrypted at rest (§5.7). No call-site changes.
3. **Per-domain cache:** port the `ID_FIELD` map (modules, module_progress,
   quiz_attempts, enrollments, event_rsvps, reflections, achievements, prayers,
   saved_verses, gifts, discussion threads/comments) so `pull` upserts and applies
   tombstones, and screens read the cache. Done domain-by-domain with each phase.
4. **Idempotency:** every offline-originated write carries a stable key; replays are
   no-ops (§2.1, §3.6) — already true at the protocol level since the server dedups
   on `mutation_id`.

---

## 5. Build / verify

- Hand-authored `NuruMember.xcodeproj` using **synchronized file groups**
  (objectVersion 70) — drop a `.swift` file in `NuruMember/` and it's compiled; no
  pbxproj edits. Matches the iPad project's approach (no XcodeGen/Tuist on the box).
- iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), iOS 17+, portrait.
- Verify gate: `xcodebuild -scheme NuruMember -destination 'platform=iOS Simulator,
  name=iPhone 17' build`, then boot + launch + screenshot.
- Smoke-test signed in: `NURU_ACCESS_TOKEN` / `NURU_REFRESH_TOKEN` launch env vars
  (Debug only) start the app authenticated against a running backend.

---

## 6. Definition of done (per screen)

A screen is "ported" when: it builds clean, renders to the design tokens, reads
live data through `MemberAPI`, writes go through `SyncEngine.writeThrough` where the
RN app queued them, the §1.9 hard-lock holds for any gated content, and it's added
to `PORT_STATUS.md`.

## 7. Cutover & RN retirement

1. Reach parity phase-by-phase (this repo), each phase shippable to TestFlight.
2. When all phases land + QA passes, **App Store release** of the native app
   replaces the RN iOS build.
3. Stop building iOS from `packages/mobile`; remove its `ios/` project.
4. Plan Android: native Kotlin port (same backend) or pause, per product call.
5. Retire `packages/mobile` once both platforms are off RN.

Cross-surface coordination, parity tracking, and the contract remain governed by
the monorepo's `docs/COORDINATED_DEV.md`, `docs/PARITY.md`, and `CONTRACTS.md`.
