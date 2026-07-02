# Figma → Code Parity Audit (native iOS)

Source of truth: Figma Make **AgqYlBEN2Sy2tA6vjBaUxE** ("Nuru Pathway app design").
Target: `NuruMember` (native SwiftUI, iPhone iOS 17+), one backend/OpenAPI contract.
Audited: 2026‑07‑02. Backend routes compared: **90 member endpoints**; iOS client
consumes **69** (`MemberAPI`).

## 1. Screen checklist (Figma component → iOS screen)

| Figma component | iOS screen | State |
| --- | --- | --- |
| `LoginScreen` | `Login/LoginView` | ✅ parity |
| `BottomTabBar` | `Shell/RootView` (Home·Pathway·Plans·Events·Chat·Give·Profile) | ✅ (native uses an **Events** tab where Figma groups events under **Community**) |
| `HomeTab` | `Home/HomeView` | ✅ wired (verse, hero, video-in-card, cell, grow grid, give) |
| `PathwayHub` | `Pathway/PathwayView` | ✅ **rebuilt to Figma** (PR #43), real data |
| `LevelsOverview` | `Pathway/LevelsMapView` ("Map view") | ✅ (PR #43) |
| `PlansTab` | `Grow/ReadingPlansView` | ✅ rebuilt (PR #41) |
| `PlanDetail` | `Grow/ReadingPlansView → PlanDetailView` | ✅ rebuilt (PR #42) |
| `ReadingDayReader` | `Grow/PlanSegmentView` / `PlanDayView` | ✅ |
| `ModuleLearn` / `LessonReader` | `Pathway/ModuleView` (Learn/Reflect tabs) | ✅ |
| `QuizScreen` | `Pathway/QuizView` | ✅ |
| `DevotionalScreen` | `Grow/DevotionalView` | ✅ |
| `MemoryVerseScreen` | `Grow/MemoryVerseView` (+ `VerseLibraryView`) | ✅ |
| `PrayerJournalScreen` | `Grow/PrayerJournalView` | ✅ |
| `MentorScreen` | `Profile/MentorView` | ✅ |
| `SpiritualGiftsScreen` | `Profile/GiftsView` + `GiftsAssessmentView` | ✅ |
| `ResourcesLibraryScreen` | `Grow/ResourcesLibraryView` | ✅ **built to Figma** (PR #44), wired `/growth/resources` |
| `CommunityTab` | `Events/EventsView` + `AnnouncementDetailView` + Prayer Wall | ✅ (restructured into the Events tab) |
| `EventDetail` | `Events/EventDetailView` | ✅ (RSVP) |
| `ChatTab` | `Chat/ChatView` | ✅ |
| `ChatThread` | `Chat/ChatThreadView` | ✅ |
| `NuruAssistant` | `Chat/NuruAssistantView` | ✅ **built to Figma** (PR #45), wired `/assistant/*` |
| `GiveTab` | `Give/GivingView` (+ receipt, statement) | ✅ |
| `ProfileTab` | `Profile/ProfileView` (+ MFA, notifications) | ✅ |
| `NotificationsScreen` | `Profile/NotificationsView` | ✅ |
| Prayer Wall (Community) | `Community/PrayerWallView` (+ detail) | ✅ |
| Cell Info | `Home/CellInfoView` | ✅ |

## 2. Gap analysis

### Cream-header pass (Figma-exact)
The Figma uses a **light cream header** (`linear-gradient 160° #f6f4ef→#efe8da`,
navy text, gold-brown `#9a7a2a` eyebrow, gold radial glow, white bordered
controls, bottom hairline) on every hub/tab and `ScreenShell` sub-page — the iOS
app had them navy. Converted to exact spec (build-verified on iPhone 17 sim):
Home, Give, Profile, Chat, Events, Devotional, Memory Verses, Prayer Journal,
Mentor. Pathway + Plans keep their navy heroes; Gifts already had a light bar.
Still navy/other (image-hero or Figma "E6 placeholder", left intentionally):
EventDetail, AnnouncementDetail, CellInfo, LevelDetail, Module, Calendar,
PrayerWall (deliberate gradient hero).

### Multi-agent parity sprint (2026-07-02, six parallel tracks)
All build-verified in one integration pass; committed per track:
- **EventDetail** → exact Figma (16:11 hero + real covers, category meta tiles,
  Figma RSVP palette, LIVE/Completed pills, ShareLink; mock roster/QR skipped).
- **ChatThread** → full "Aurora" (light bubbles, 8-color sender-accent hash, run
  grouping, in-bubble reaction footers, day separators, prayer chip; cream header).
- **Module + Quiz** → Figma one-question pager + ceremonies, server-authoritative
  scoring preserved; parchment lesson page, mock audio removed.
- **Give** → compose flow + annual statement from real history (receipt got the
  cream header; full receipt-ceremony restyle = open follow-up).
- **Day reader / Verse library / Gifts assessment** → ReadingDayReader serif
  passage + pull-quote; practice sheet; one-question Likert flow, server scoring.
- **Security/speed sweep** → ThisDeviceOnly keychain (no iCloud sync), dedicated
  URLSession (fail-fast, no cookies), ImageIO downsampling >2400px, WAL/SHM file
  protection; verified single-flight refresh, zero logging, no ATS exceptions.
- Also: Login brand mark exact; Notifications rows exact (reward gold tiles,
  unread accent bar, category tones).

### Closed this session
- **Pathway** was the wrong Figma component (levels-overview). Rebuilt to `PathwayHub`
  (hero for current level → journey rail → inline real module trail → milestones →
  summit), bound to `/me/pathway` + `/levels/{n}/modules` + `/me/achievements`.
  Modules render in progression order. "Map view" preserves the old overview.
- **Resources** was a `PlaceholderScreen` → real `ResourcesLibraryScreen` + `/growth/resources`.
- **Nuru Assistant** card was inert → real `NuruAssistant` screen + `/assistant/chat`+`/history`.

### Open (deferred, ranked)
| Gap | Backend | Effort | Note |
| --- | --- | --- | --- |
| `LevelComplete` celebration screen | (client) | S | No dedicated screen; completion just marks done |
| Per‑pillar **score detail** (`me/scores/{word,prayer,habits,curriculum,attendance}`) | ✅ exists, **unused** | M | App shows the summary ring only |
| **Cell milestones** on Cell Info (`cells/:id/milestones`) | ✅ exists, **unused** | S | Enrich `CellInfoView` |
| Pathway **trail encouragements** (`levels/:n/encouragements`) | ✅ exists, **unused** | M | PathwayHub uses milestones instead; badges/mentor/announcements inline are the old `PathwayTab` design |
| **Cohort discussions** (`community/threads`) | ✅ exists, **unused** | M | No community/threads screen (native has no Community tab) |
| Event **QR check‑in** (`QrScanner`) | n/a in dev | M | `EventDetailView` has RSVP, no scanner |
| `SpacePreview` before joining a space | — | S | Space rows open the thread directly |
| Standalone `ReflectionComposer/Status` | folded | — | Reflection is folded into `ModuleView`'s Reflect tab (functional) |
| Notification prefs **sync** | ❌ no member route | S+BE | Profile push/email/sms are device‑local `@AppStorage`; backend has a `notification_preferences` table but only onboarding writes it |

## 3. Backend integration report
- iOS consumes **69** endpoints across pathway, growth (devotional/verses/plans/
  resources/mentor/gifts), prayer wall, chat, assistant, events/calendar, giving,
  home, scores (summary), rhythm, achievements, profile/MFA/location.
- **Available but unused (real data, no screen):** per‑pillar `me/scores/*`,
  `cells/:id/milestones`, `levels/:n/encouragements`, `community/threads*`,
  `members/:id/achievements`, `announcements/:id/open`, `me/prayers/:id/share-to-wall`.
- **Data quality (local dev only):** level 1 mixes 10 real curriculum modules
  (seq 1–10) with 20 seeded **"Dev Module N"** rows (seq 101–120, completed) → the
  "20/30" progress. Real prod data is separate; the UI orders completed‑first so it
  reads correctly regardless.

## 4. Blockers
- **Android (Kotlin):** no native app exists, and this environment has **no JDK /
  Android SDK / Gradle** (`java` not locatable, `ANDROID_HOME` empty) → an APK/AAB
  **cannot be built here**. See `../ANDROID_FOUNDATION.md` for the scaffold + plan.
- **AI provider:** `/assistant/chat` returns `UPSTREAM_UNAVAILABLE` in local dev
  (no provider key). The screen handles it gracefully; verify on prod once keyed.
- **Signing:** free Apple Development cert (7‑day) — the dev profile must be trusted
  on device once (Settings → General → VPN & Device Management → Trust).
