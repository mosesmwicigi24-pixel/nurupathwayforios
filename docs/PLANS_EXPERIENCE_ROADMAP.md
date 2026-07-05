# Reading Plans — world-class experience roadmap

Design direction from deep research (YouVersion, Lectio 365, Dwell, Hallow, Glorify,
First 5, She/He Reads Truth, Bible in One Year, Abide + Duolingo/Headspace mechanics,
and the anti-gamification counter-example Manna).

**Guiding principle:** borrow Duolingo's *mechanics* but Glorify/Manna's *tone* —
grace-first, Scripture-first, beautiful. Streaks with silent auto-freezes, milestone-
only celebrations, warm specific reminders, no shame loops. Lean on Nuru's **cells**
(the one thing Duolingo can't touch).

## Status (2026-07-05)
- #1 Resume + reminders — ✅ DONE (Home + Plans "Continue · Day N" banners; daily local reminder).
- #2 Grace-first streak — ✅ DONE (backend grace-days deployed `12bdf48`; "N days with God" copy; Quiet Mode toggle in Profile).
- #3 Milestone keepsake — ✅ DONE (plan-completion keepsake: seal, blessing, fireworks, shareable card, "continue your journey").
- #4 Browse + reader comfort — ◐ MOSTLY DONE (browse cards show progress rail + "Day N of M"/COMPLETED; warm night/sepia reader mode via moon toggle). REMAINING (minor): hero "For you today" + intent rows on browse.
- **Android parity** — ☐ the entire plans experience (single-scroll reader, dwell, resume, streak grace copy, keepsake, browse progress) still to port to Kotlin/Compose.

Member iOS builds this arc: 8 (single-scroll reader) → 18 (night mode). Backend: grace-first streak deployed.

## Build order (user picked all four, 2026-07-05)

1. **Resume + reminders everywhere** — "Continue · Day N of Plan" card on Home + Plans
   "In progress" first + cross-surface resume chips + warm deep-linking reminders at a
   user-set time (one gentle evening grace-nudge max, then stop).
2. **Grace-first streak** — "days with God" flame + calendar; up to 2 silent auto
   grace-days (soft navy dot, never a broken heart); Quiet Mode to hide it entirely.
3. **Milestone keepsake celebration** — ordinary days quiet; Day 7 / plan-finish add a
   shareable keepsake verse-card + badge + "What's next" plan (honor level-gating).
4. **Browse cards + reader Aa/night mode** — hero "For you today", intent rows
   (anxious / new to faith / for your cell / 5-min), progress rings on cards; reader
   gold verse-numbers, Aa size menu, warm night/sepia mode, focus-fade chrome,
   "Make a card" on any verse.

## Later multipliers
- **Read with your cell** — shared day-dots, per-day "Talk it Over together" thread,
  person-framed nudges ("Mary is on Day 5").
- **Read-it-to-me audio** bar over the same scroll (TTS or recorded).
- Home-screen widget (flame + Continue), length/mode tiers ("Short on time?").

## Already shipped (member iOS)
- Single-scroll reader (was tab-through); the day IS the reading; quick-step jump chips.
- Dwell-based per-part completion (scroll-speed aware) + "slow down" nudge.
- Bottom CTA; tab bar hidden inside a plan; keyboard Done + dismiss.
- Bigger reading type + gaps + subtitles; ~5s fireworks celebration; "Continue the plan →".
- Doubled-scripture-quote fix; mid-length browse bucket.
