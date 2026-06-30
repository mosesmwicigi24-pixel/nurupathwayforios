# Pixel-redesign to the RN screenshots (`~/Downloads/iphone`)

The 55 screenshots in `~/Downloads/iphone` (IMG_1866–IMG_1920) are the authoritative
spec for the look/feel/UX of the real RN NuruPlace app. We replicate them **exactly**
into the native Swift app — colour, card, spacing, icon, copy, flow — page by page.

## STATUS — COMPLETE (PRs #1–#15)
**All 55 screens ported, built, and screenshot-verified.** Full inventory:
Profile/Account · Pathway · Level detail · Module · Quiz · Home dashboard ·
Chat (Nuru Connect) + DM/Space threads · Events tab · Calendar · Event detail ·
Announcement detail · Plans · Plan detail/day · Plan segment (Watch) · Give ·
Statement · Receipt · Devotional · Memory verses · Prayer Wall (list+detail) ·
Prayer Journal · Your Calling (gifts) · Gifts assessment · Mentor · Notifications · Login.

**Backend↔Swift wiring verified end-to-end** (#19): all 32 primary screen endpoints
return 200 + decodable. Fixed the `/home/featured-cell` 500 (local replica DSN pointed
at a stale DB — prod unaffected; replica is a true replica there).

**Performance** (#15): `CachedAsyncImage` (decoded-image NSCache over disk URLCache,
off-main decode, load cancellation) replaces stock AsyncImage at all 16 sites →
no re-download/re-decode flicker.

**Remaining (separate, larger efforts, not yet started):** offline-first sync engine +
SQLCipher store (§1.7 guardrail); rich admin-content demo seeding; list pagination.

**Authority:** full autonomous decision-making; pick the best engineering/UI choice and
proceed. **Cadence:** a **PR per page** (branch → build → screenshot-verify on the live
local backend → commit → push → `gh pr create` → squash-merge so `main` stays current).

Downscaled review copies: scratchpad `catalog/IMG_*.png`. Re-read the full-res original
(`~/Downloads/iphone/IMG_*.PNG`) when building each screen.

## Screen catalog (image → screen → key deltas vs current build)

| Imgs | Screen | Notes / deltas to match |
|------|--------|--------------------------|
| 1866–1869 | **Profile / Account** | Navy header (ACCOUNT, gear, avatar+gold level coin, name, email, Level pill). Cards: Personal Information (editable rows w/ pencils, flag, language chips), Security & Login (change pw, 2FA toggle, active sessions), Connected Accounts (Google/FB/IG/X/LinkedIn/YouTube + Connect/Disconnect), Social Links, Notifications (push/email/sms toggles), Achievements (badges), Milestones, Certificates, Display (text size S/D/L), Privacy (share location toggle), Help & Privacy (language/help/policy), Sign out + Delete account, version. |
| 1870–1876 | **Give** | Navy header "GIVE / Sow into the Kingdom / generosity tagline / year pill". Repeat-last-gift card. Fund cards (Tithe/Offering/Gift/Mission/Discipleship, proper icons+tints). Amount card "KSh" big serif + presets + Custom. Frequency seg. CHOOSE HOW TO PAY reorderable method list (M-Pesa/Airtel/Equity SOON/Card/Apple-Google SOON/PayPal, drag handles, up/down). Cover-the-fee. ACTIVE SCHEDULES cards. Recent giving + View statement. Scripture strip (2 Cor 9:7). Secure note. Sticky gold "Give KSh X". Custom keypad sheet. M-Pesa number sheet. |
| 1877 | **Giving Statement** | Navy header "GIVING STATEMENT" + download. Total given big. Grouped-by-day cards (fund icon, name, time·method·ref, amount, status chip). |
| 1878 | **Giving Receipt** | Navy header w/ status circle (GIFT FAILED/✓), amount, fund, via M-PESA chip. Confirmation text. TRANSACTION JOURNEY 2 cards (initiated/declined). Account/Fee/Total row. M-Pesa receipt no (copy). "RECEIVED WITH THANKS" seal. Scripture. Share/Save PDF. |
| 1879–1883 | **Chat = "Nuru Connect"** | Greeting header (GOOD EVENING · MOSES / Nuru Connect / "You're all caught up" / bell+badge). Search bar. "Quick help from Nuru" AI card (purple gradient + AI badge). VERSE FOR TODAY card. Segments #My Space/DM/My Groups (counts). My Space: spaces list (colored # avatars, name, last msg, member dots+count, Active pill, day). DM: stories row (ME+people rings) + Direct Messages list. Groups: empty state. Gold pencil FAB. Threads: "Held in confidence" banner, bubbles (mine navy right, theirs white left), read receipts ✓✓/Delivered, quick-reply chips, composer (avatar + "+" + field + AI sparkle + emoji + gold mic). Space thread: public header, image messages, reactions. |
| 1884–1885 | **Events = "Gathered together"** | Navy header. Month week-strip card (selectable days, event dots). Calendar card (navy/gold). Today/Upcoming/RSVPs seg. Search. Category chips (All/Worship/Cell/Leaders/Youth). Today's gatherings. SERIES YOU FOLLOW (Following/Follow). ANNOUNCEMENTS. |
| 1886 | **Calendar** | Navy header "June 2026". Month grid card (TODAY + ‹›, selected day navy, gold ring today, category dot legend). Day's events list. |
| 1887–1889 | **Event detail** | Parallax image hero (WORSHIP badge, "Happening now" pill, title). Date/Time/Where/Going chip grid. Add to calendar/Share. About. WHO'S GOING avatars. WILL YOU BE THERE? Going/Maybe/Can't seg. WHO'S COMING/Buzzing feed (hype composer + attendee posts w/ photos + Going chips + reactions + quick replies). |
| 1890 | **Plans tab** | Navy header "READ·REFLECT·APPLY / Plans". ACTIVE PLANS card (title, Day X of N, progress). BROWSE PLANS list (image, N DAYS badge, title, subtitle). |
| 1891–1892 | **Plan detail + day** | Parallax hero (FOUNDATIONS·21 DAYS, title). About card. Day chips (1✓/2/3/4). Day N of M + "X done". Day view: "Two Roads", segment list (Watch/Today's Reading/Devotional/Talk it Over, chevrons), Start Reading CTA. |
| 1893–1894 | **Plan segment (Watch)** | Immersive video player + "Start Watching"; segment detail (thumbnail+play, title, desc, Day x of y, next arrow). |
| 1895–1898 | **Pathway tab** | Navy header (YOUR PATHWAY / "Good evening, Moses" / Level X of 7 · level name / 3-day streak pill / progress ring %). "PICK UP WHERE YOU LEFT OFF" continue card. REMINDERS card. THE JOURNEY: level cards (IN PROGRESS/LOCKED, module trail, View all, stats, Certificate awaiting), scripture interstitials, "word from discipler" card, EVENT/WATCH cards, "THE SUMMIT / Commissioned" hero. |
| 1899 | **Level detail** | Parallax hero (open Bible, "Foundations of Faith / Foundations"). "1 of 10 modules 10%" + stats. WALK IN THE LIGHT verse card. WALK IT WITH YOUR DISCIPLER chat card. YOUR MODULE TRAIL "Learn step by step" + module cards (DONE 100% w/ min·Quiz, LOCKED). |
| 1900–1920 | **TBD — review per screen** | Likely: Module detail, Quiz, Devotional, Memory Verse, Reading-plan reader, Prayer Wall, Home dashboard, Nuru Assistant (AI), Login. Read full-res when building each. |

## Build order (PR per page)
Profile → Pathway → Level detail → Module → Quiz → Home → Chat (Nuru Connect) → DM/Space threads
→ Events → Calendar → Event detail → Plans → Plan detail/day → Give → Statement → Receipt
→ Devotional/MemoryVerse/PrayerWall refinements → Nuru Assistant → remaining (1900–1920).

## Verify rig
Local Postgres + backend on :8080 (see [[native-ios-member-app]] memory). Screenshot authed via
`SIMCTL_CHILD_NURU_ACCESS_TOKEN`/`NURU_TAB`/`NURU_SCREEN`. Compare side-by-side with the IMG_*.
