
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
