# CLAUDE.md — Nuru Member (iOS)

Guidance for AI assistants (and humans) working in this repository. Read this before making changes.

## What this is

**Nuru Member** is the native **SwiftUI iPhone app** for the **Nuru Place Discipleship Pathway** — a Christian church / discipleship platform. Users see it as **"Nuru Place"** (`CFBundleDisplayName`); widgets show as "Nuru". It's the member-facing sibling of a separate native iPad **admin** portal.

This repo **replaces the iOS surface of an existing React Native member app** with a true native iOS client, talking to the **same backend and OpenAPI contract** at `https://pathway.nuruplace.org/v1`. It's "step one of retiring React Native entirely" (decision 2026-06-30; see `MIGRATION_PLAN.md`).

Core member features (see `Features/`):
- **Pathway** — 7-level discipleship curriculum (levels → modules → lessons → quizzes/exams), server-authoritative gating (a member never sees content above `current_level` — "§1.9 hard-lock").
- **Grow / Plans** — daily rhythm (devotional, memory verses), reading plans with a single-scroll day reader, prayer journal, verse library, "Talk it Over" cell conversation.
- **Home** — server-driven dashboard: next-best-action hero, daily rhythm ring, 28-day growth score, verse-of-the-day.
- **Community** — public Prayer Wall + detail, discussions.
- **Chat ("Nuru Connect")** — DMs, spaces/groups, thread reactions, AI compose help, Cloudinary image attachments, staff broadcast.
- **Events ("Gathered together")** — events, RSVP, calendar, "buzz" posts / "Who's coming" event wall (photo posts + reactions — the most recent work, builds 39–41), QR check-in scanner.
- **Give** — online-only giving (M-Pesa/Airtel/PayPal; Card path pending Stripe). Money is **never** offline-queued.
- **Profile** — account, gifts assessment ("Your Calling"), mentor/discipler, notifications, settings, scores.
- **Nuru Radio** — live HLS station, scheduled shows, listener-presence heartbeat, floating Dynamic-Island mini-player.
- **Home-screen widgets** (NuruWidgets) — static `nuru://` deep-link doors: Pathway, Chat, Radio.

Key docs: `README.md`, `MIGRATION_PLAN.md`, `PORT_STATUS.md`, `REDESIGN_PLAN.md`, `docs/PLANS_EXPERIENCE_ROADMAP.md`, `docs/BACKEND_AUDIT.md`, `docs/FIGMA_PARITY_AUDIT.md`.

## Repository layout

```
NuruMember/                    App target source (~94 Swift files)
NuruMember.xcodeproj/          Xcode project (objectVersion 70, synchronized file groups)
NuruWidgets/                   WidgetKit app-extension target
Config/NuruMember-Info.plist   Merged Info.plist (GENERATE_INFOPLIST_FILE stays YES)
docs/                          BACKEND_AUDIT.md, FIGMA_PARITY_AUDIT.md, PLANS_EXPERIENCE_ROADMAP.md
README.md  MIGRATION_PLAN.md  PORT_STATUS.md  REDESIGN_PLAN.md
```

> **No pbxproj edits needed.** The project uses `PBXFileSystemSynchronizedRootGroup` (synchronized file groups, objectVersion 70). Any `.swift` file dropped under `NuruMember/` is compiled automatically — **no XcodeGen/Tuist, no SPM, no manual project registration.**

### Inside `NuruMember/`
- `NuruMemberApp.swift` — `@main` App entry. Wires `AuthStore`, `SyncCoordinator.shared`, `TabRouter`; splash → `RootView` (authed) / `LoginView`. Registers fonts, configures caches + nav-bar appearance, forces `.preferredColorScheme(.light)`.
- `Theme/` — `NuruTheme.swift` (design tokens, `enum Nuru`), `LucideIcons.swift` (Lucide set + `Icon` view), `Interactions.swift` (haptics).
- `Networking/` — `APIClient.swift` (URLSession actor), `MemberAPI.swift` + nine `MemberAPI+*.swift` extensions (Community, Discipleship, Engagement, Exam, GrowExtras, Ops, Profile, Progression), `ImageCache.swift` (`CachedAsyncImage`).
- `Auth/` — `AuthStore.swift` (session `ObservableObject`), `KeychainStore.swift` (token vault).
- `Offline/` — `OfflineStore.swift` (`PendingMutation`, `LocalStore` protocol, `SyncEngine`), `EncryptedSQLiteStore.swift` (SQLCipher-style, `-lsqlite3`), `SyncCoordinator.swift` (`@MainActor` connectivity + flush/pull, `NWPathMonitor`).
- `Models/` — 13 files of wire DTOs mirroring the backend's `dto.ts`; decoded with `.convertFromSnakeCase`.
- `Notifications/LocalNotifier.swift` — bridges server `/me/notifications` to local iOS notifications (no APNs yet — needs a paid Apple team).
- `Features/` — one folder per area: `Home`, `Pathway`, `Grow` (+ `Plans`), `Community`, `Chat`, `Events`, `Give`, `Profile`, `Discipleship`, `Radio`, `Login`, `Shell` (`RootView` tab shell), `Shared` (Components, CelebrationCenter, FitImage, ImageLightbox, VideoPlayerPage, AiDraftButton, SafeArea).
- `Resources/Fonts/` — Inter + Fraunces (OFL). `Assets.xcassets`.

## Tech stack

- **Swift 5.0**, **iOS 17.0** deployment target. **Pure SwiftUI** (`@main struct NuruMemberApp: App`), with thin UIKit use for `UINavigationBarAppearance`, safe-area insets, `UIApplication`.
- **iPhone-only, portrait** app target (`TARGETED_DEVICE_FAMILY = 1`). Widgets target is `1,2`. **Light mode only.**
- **No dependencies / no package manager** — only system frameworks (Foundation, SwiftUI, WidgetKit, UserNotifications, Network, Combine, CoreText, AVFoundation). Links `-lsqlite3` for the encrypted store.
- **Backend:** custom REST API (not Firebase/Supabase), base `https://pathway.nuruplace.org/v1`. Bearer JWT (access + refresh). Media uploads go **directly to Cloudinary** via server-signed params. Debug simulator builds hit `http://localhost:8080/v1`; override with the `NURU_API_URL` env var.
- `DEVELOPMENT_TEAM = SGC7566QY6`, automatic signing. Built with Xcode 16+.

## Build / run

```bash
xcodebuild -project NuruMember.xcodeproj -scheme NuruMember \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/nuru-member-dd build

xcrun simctl install "iPhone 17" \
  /tmp/nuru-member-dd/Build/Products/Debug-iphonesimulator/NuruMember.app
xcrun simctl launch "iPhone 17" org.nuruplace.member
```

- **Bundle IDs:** app `org.nuruplace.member`; widget extension `org.nuruplace.member.NuruWidgets`.
- **Targets:** `NuruMember` (app, embeds the widget appex) and `NuruWidgets` (WidgetKit app-extension).
- **Debug** → localhost backend; **Release** → prod. Run the local backend with `pnpm --filter @nuru/backend dev` in the monorepo.
- **Debug-only launch env hooks** (headless/screenshot testing, via `SIMCTL_CHILD_` prefixes): `NURU_ACCESS_TOKEN` / `NURU_REFRESH_TOKEN` (start signed in), `NURU_TAB` (open a tab), `NURU_SCREEN`, `NURU_API_URL`.
- **Verify gate** (MIGRATION_PLAN §5): `xcodebuild … build`, then boot + launch + screenshot on an iPhone 17 sim.

### Versioning / build numbers
- `MARKETING_VERSION = 1.1`. `CURRENT_PROJECT_VERSION` is the build number (currently **41** — "build 41").
- **Bump `CURRENT_PROJECT_VERSION` on every shipped feature build**, and it must be bumped in **all three build configurations** in `project.pbxproj` (app Debug, app Release, widget) — they must stay in lockstep.
- The build number appears in the commit subject as `(build NN)`.

## Architecture

MVVM-ish SwiftUI — deliberately **not** a Redux port.

- **State:** per-screen `@StateObject`/`@Published` view models + a single app-wide `AuthStore` (`@MainActor ObservableObject`: `isAuthenticated`, `me`, `booting`). Global environment objects injected in `NuruMemberApp`: `AuthStore`, `SyncCoordinator.shared`, `TabRouter`.
- **Networking:** `actor APIClient` (`APIClient.shared`) — a URLSession actor. Injects the `Bearer` JWT, uses snake↔camel case conversion, bounded timeouts, `waitsForConnectivity=false` (offline-first fail-fast), no cookie/credential persistence. Implements **single-flight 401 refresh** (`refreshTask`): concurrent 401s share ONE refresh call because refresh tokens are one-time-use/rotated (reuse trips server reuse-detection). `resolveBaseURL()` picks env → localhost (Debug sim) → prod. Sentinels: `EmptyResponse`, `RawJSON` (skips key conversion; used by sync-pull).
- **Endpoint facade:** `enum MemberAPI` with static async methods, split across `MemberAPI.swift` + `MemberAPI+*.swift`. **Screens call `MemberAPI.*`, never the raw client.** Lists use a generic `Envelope<T>` (`{ "data": [...] }`). Writes carry `clientMutationId`/`idempotencyKey`/`clientEventId` UUIDs so the server dedupes replays.
- **Auth/persistence:** `KeychainStore` holds `nuru.member.at` / `nuru.member.rt`. `AuthStore.bootstrap()` leaves the splash immediately once a Keychain session exists (never gates on `/me`).
- **Offline-first:** `OfflineStore.swift` defines `PendingMutation` (durable queue, monotonic per-device `seq`), a `LocalStore` protocol, and `SyncEngine` (enqueue/push/pull). `EncryptedSQLiteStore` is the encrypted cache; `SyncCoordinator` (`@MainActor`) owns `NWPathMonitor`, `isOnline`/`pendingCount`/`isSyncing`, and flush triggers (launch, reconnect, foreground, post-enqueue). **Money is never queued (§5.6).** ⚠️ Much of the offline engine is still a **skeleton** — most feature writes are currently online-first and are to be retrofitted onto `SyncEngine.writeThrough`.
- **Navigation shell** (`Features/Shell/RootView.swift`): a **hand-rolled 7-tab container**, NOT `TabView` (a stock 7-tab `TabView` collapses tabs 5–7 into a "More" nav controller on iPhone). Tabs: Home · Pathway · Plans · Events · Chat · Give · Profile. `TabRouter` holds `selected`, cross-tab deep links (`pathwayLink`/`planLink`/`eventLink`/`announcementLink`), `chromeHidden`, `onAirBarVisible`. Custom navy `NuruTabBar` with a matched-geometry gold pill. Tabs are lazily created and kept alive; each tab view is returned as `AnyView` to keep `RootView`'s type small (avoids a Swift metadata-demangler stack overflow / `EXC_BAD_ACCESS` on device).
- **Deep linking:** `nuru://` scheme (`onOpenURL`) from widgets → tabs. Tapped iOS notifications route by `template` to targets via `NotificationCenter` names (`nuruNotificationTap`, `nuruOpenNotifications`, `nuruOpenRadio`). Screen telemetry: `ScreenTracker.record` → `POST /me/activity/screens`.
- **Design system:** `enum Nuru` tokens — warm paper `0xF6F4EE`, navy `0x0B1F33`, gold `0xC89B3C`; radii (`R.card=24`), 8pt spacing grid (`S`), Inter (body) + Fraunces (serif display), one soft shadow. Ported 1:1 from the RN app's `tokens.ts`.

## Conventions

**Commits** — Conventional Commits with a build tag and PR ref, warm/product-voiced subject:
```
feat(events): buzz post photo shows full — card grows to the image, no crop (build 41) (#50)
```
Types: `feat`, `fix`, `style`, `polish`, `docs`. Scope = feature area (`events`, `plans`, `pathway`, `home`, `notifications`, `radio`, `widgets`, `nav+readers`, `global`). Nearly every user-facing commit ends with `(build NN)` and `(#PR)`.

**Cadence** (REDESIGN_PLAN) — **a PR per page/screen**: branch → build → screenshot-verify on the live local backend → commit → push → open PR → squash-merge so `main` stays current. Default branch is `main`; work happens on `claude/…` branches (yours: `claude/claude-md-docs-51n3sn`).

**File organization** — feature-first folders under `Features/<Area>/`; models grouped by domain in `Models/`; networking split by domain into `MemberAPI+<Area>.swift`. No file needs project registration (synchronized groups).

**Naming** — SwiftUI views `<Thing>View`; view models per-screen; DTOs are plain `Codable, Sendable` structs; design tokens under `Nuru`; icons via `Lucide`/`Icon`.

**Contract section refs in comments** — `§1.7` (offline), `§1.9` (pathway gating hard-lock), `§5.3` (auth/2FA), `§5.6` (money never queued), `§5.7` (keychain/encryption at rest). These come from the monorepo contract docs.

`.gitignore` excludes `build/`, `DerivedData/`, `xcuserdata/`, `.swiftpm/`, `.build/`, `.DS_Store`.

## Migration / porting context

This is a **client rewrite from React Native (TypeScript) to native SwiftUI**, keeping the backend + OpenAPI contract fixed (source of truth). Architecture mapping (MIGRATION_PLAN §2): `theme/tokens.ts` → `NuruTheme.swift`; `api/client.ts` → `APIClient.swift`/`MemberAPI.swift`; Redux `store/*` → `@StateObject` view models + `AuthStore`; RN `syncEngine.ts` + op-sqlite → `Offline/OfflineStore.swift` + `EncryptedSQLiteStore` (SQLCipher); `RootNavigator.tsx` → `RootView.swift`.

**Status** (PORT_STATUS.md + REDESIGN_PLAN.md): all reference screenshots ported/built/screenshot-verified, backend↔Swift wiring verified end-to-end, `CachedAsyncImage` in place. Core layer (tokens, shared components, API client, Keychain, `AuthStore`) is **done**. **Still pending:** full offline-first retrofit onto `SyncEngine.writeThrough`, APNs push (needs paid Apple team), list pagination, richer seed content, some Profile settings detail, several Chat/Community secondary screens, and the giving **Card path (Stripe)**.

## Gotchas

1. **Never bump the build number in only one config** — `CURRENT_PROJECT_VERSION` must match across all three build configurations, or the app and its embedded widget mismatch.
2. **Don't switch `RootView` to a stock `TabView`** — 7 tabs would collapse into "More". The hand-rolled shell is intentional, as is the `AnyView` erasure (avoids a device-only crash).
3. **Money is never offline-queued** (§5.6) — giving writes are always online-first.
4. **Pathway gating is server-authoritative** (§1.9) — never surface content above the member's `current_level` client-side.
5. **New Swift files just work** — synchronized file groups compile everything under `NuruMember/`; don't hand-edit `project.pbxproj` to add files.
6. **No APNs yet** — notifications are local-only via `LocalNotifier` on foreground sync until a paid Apple team is available.
