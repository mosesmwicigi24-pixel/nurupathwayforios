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
- ✅ LevelsScreen → `Features/Pathway/PathwayView.swift` (level trail, §1.9 lock)
- ✅ LevelScreen → `Features/Pathway/LevelDetailView.swift` (module trail)
- ✅ ModuleScreen → `Features/Pathway/ModuleView.swift` (lesson + complete/quiz CTA)
- ✅ QuizScreen → `Features/Pathway/QuizView.swift` (all 5 question kinds, server-scored result)
- ☐ ReflectionScreen (module reflection review state — M3)
- ◑ LevelCompleteScreen (quiz result screen done; standalone level-complete ceremony pending)
- Gating: ✅ `Features/Pathway/LevelGating.swift` (§1.9, server-authoritative)

### Phase 2 — Daily rhythm & Word (hosted in the new "Grow" tab)
- ✅ DevotionalScreen → `Features/Grow/DevotionalView.swift` (+ save reflection → rhythm)
- ✅ MemoryVerseScreen → `Features/Grow/MemoryVerseView.swift` (reveal + practice)
- ✅ ReadingPlansScreen → `Features/Grow/ReadingPlansView.swift`
- ✅ PlanDetailScreen → `PlanDetailView` (start + day list)
- ✅ PlanDayScreen → `PlanDayView` (segments + complete day)
- ✅ PrayerJournalScreen → `Features/Grow/PrayerJournalView.swift` (add/edit/answer/delete)
- ✅ VerseLibraryScreen → `Features/Grow/VerseLibraryView.swift` (add/delete)
- Hub: `Features/Grow/GrowView.swift`. NOTE: writes are online-first for now;
  retrofit onto `SyncEngine.writeThrough` in the offline-engine phase.

### Phase 3 — Community (hosted in the "Community" tab)
- ✅ PrayerWallScreen → `Features/Community/PrayerWallView.swift` (hero, sort, cards, compose) — exact port
- ✅ PrayerWallDetailScreen → `Features/Community/PrayerWallDetailView.swift` (reactions, comments, composer) — exact port
- Hub: `Features/Community/CommunityView.swift`
- ✅ ChatScreen → `Features/Chat/ChatView.swift` (inbox: conversations + discover spaces)
- ✅ ChatThreadScreen → `Features/Chat/ChatThreadView.swift` (bubbles, reactions, composer)
- ☐ NewMessageScreen ☐ ThreadScreen ☐ CohortDiscussionsScreen ☐ SpacePreviewScreen
- NOTE: voice-note record/playback shown as a tag for now (audio subsystem ported
  later); compose writes are online-first (retrofit onto SyncEngine.writeThrough).
  Note: the stray top chevron seen in screenshots is a harness artifact of
  deep-launching a non-default tab (NURU_TAB); it does not appear when a tab is
  tapped normally (Home, the default, never shows it).

### Phase 4 — Events & calendar
- ✅ EventsScreen → `Features/Events/EventsView.swift` (navy header + pulse row,
  live/featured hero, week-window segments, photo event cards) — exact
- ✅ EventDetailScreen → `Features/Events/EventDetailView.swift` (hero, RSVP
  Going/Maybe/Can't-go, who's-going roster, description) — core ported
- ✅ NotificationsScreen → `Features/Profile/NotificationsView.swift` (typed rows,
  mark-all-read, unread dots, deep-link routing) — exact (reached from Home bell + Profile)
- ☐ CalendarScreen ☐ AnnouncementDetailScreen
- NOTE: hero + event cards not render-verified (dev DB has 0 seeded events);
  empty state + header verified. Buzz-feed photo wall on detail deferred.

### Phase 5 — Giving (online-only, §5.6)
- ✅ GivingScreen → `Features/Give/GivingView.swift` (year pill, 5 funds, big
  amount + presets, frequency, methods, cover-fee, sticky CTA, recent giving,
  STK/success/failed ceremony) — exact. Mobile-money + PayPal wired; **Card path
  flagged "soon"** (needs Stripe SDK, client-side tokenisation, SAQ-A).
- ☐ GivingReceiptScreen ☐ GivingStatementScreen ☐ recurring-schedule manager

### Phase 6 — Profile & growth
- ☐ ProfileScreen (full) ☐ GiftsScreen ☐ MentorScreen ☐ WatchScreen
- ☐ ResourcesLibraryScreen ☐ NuruAssistantScreen

## Verification log
- 2026-06-30: `xcodebuild` Debug/iPhone 17 simulator → **BUILD SUCCEEDED**;
  app boots and renders the Login ceremony screen (fonts load, tokens applied).
- 2026-06-30: Phase 1 Pathway (Levels→Module→Quiz) added → **BUILD SUCCEEDED**.
  Runtime render of the authed Pathway tab pending a live backend session.
- 2026-06-30: Phase 2 Grow (Devotional, Memory Verses, Reading Plans, Prayer
  Journal, Verse Library) added → **BUILD SUCCEEDED**; app boots clean. Authed
  runtime render pending a live backend session.
