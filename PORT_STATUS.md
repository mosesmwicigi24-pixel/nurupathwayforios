# Port status — RN screens → native SwiftUI

`✅ done · ◑ in progress · ☐ not started`. 37 RN screens total. See
[MIGRATION_PLAN.md](MIGRATION_PLAN.md) §3 for phase grouping.

## Core layer
- ✅ Design tokens (`Theme/NuruTheme.swift`)
- ✅ Shared components — Card, PButton, BrandMark, NuruField
- ✅ API client — URLSession actor, single-flight 401 refresh
- ✅ Keychain token vault (§5.7)
- ✅ AuthStore — bootstrap, login, /me, sign-out
- ◑ Offline engine — queue + cursors + push/pull **skeleton**; SQLCipher store
  and per-domain cache pending
- ☐ `writeThrough` helper (online-first → queue on network error)
- ☐ Connectivity monitor (NWPathMonitor)
- ☐ Push notifications (APNs) — replaces @notifee/react-native

## Screens

### Phase 0 — slice (DONE)
- ✅ LoginScreen → `Features/Login/LoginView.swift` (+ 2FA)
- ✅ HomeDashboardScreen → `Features/Home/HomeView.swift`
- ◑ ProfileScreen (minimal: identity + sign-out) → `Features/Shell/RootView.swift`

### Phase 1 — Pathway
- ☐ LevelsScreen ☐ LevelScreen ☐ ModuleScreen ☐ QuizScreen
- ☐ ReflectionScreen ☐ LevelCompleteScreen

### Phase 2 — Daily rhythm & Word
- ☐ DevotionalScreen ☐ MemoryVerseScreen ☐ ReadingPlansScreen
- ☐ PlanDetailScreen ☐ PlanDayScreen ☐ VerseLibraryScreen ☐ PrayerJournalScreen

### Phase 3 — Community
- ☐ ChatScreen ☐ ChatThreadScreen ☐ NewMessageScreen ☐ ThreadScreen
- ☐ CohortDiscussionsScreen ☐ PrayerWallScreen ☐ PrayerWallDetailScreen
- ☐ SpacePreviewScreen

### Phase 4 — Events & calendar
- ☐ EventsScreen ☐ EventDetailScreen ☐ CalendarScreen
- ☐ AnnouncementDetailScreen ☐ NotificationsScreen

### Phase 5 — Giving (online-only, §5.6)
- ☐ GivingScreen ☐ GivingReceiptScreen ☐ GivingStatementScreen

### Phase 6 — Profile & growth
- ☐ ProfileScreen (full) ☐ GiftsScreen ☐ MentorScreen ☐ WatchScreen
- ☐ ResourcesLibraryScreen ☐ NuruAssistantScreen

## Verification log
- 2026-06-30: `xcodebuild` Debug/iPhone 17 simulator → **BUILD SUCCEEDED**;
  app boots and renders the Login ceremony screen (fonts load, tokens applied).
