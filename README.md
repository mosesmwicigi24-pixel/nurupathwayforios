# Nuru Place — native iOS member app

The **native SwiftUI member app** for Nuru Place Discipleship Pathway. This repo
replaces the iOS surface of the React Native member app (`packages/mobile` in the
`pathway` monorepo) with a true native iOS app over the **same backend + OpenAPI
contract** (`https://pathway.nuruplace.org/v1`). It is the member-facing sibling of
the native iPad **admin** portal (`iphone/ios-native/NuruPortal`).

See **[MIGRATION_PLAN.md](MIGRATION_PLAN.md)** for the full plan and
**[PORT_STATUS.md](PORT_STATUS.md)** for screen-by-screen progress.

## Requirements

- Xcode 16+ (built with Xcode 26.5), iOS 17+ deployment target, iPhone-only.
- No package manager / codegen needed — the project uses Xcode **synchronized file
  groups**, so any `.swift` added under `NuruMember/` is compiled automatically.

## Build & run

```bash
# Build for the simulator
xcodebuild -project NuruMember.xcodeproj -scheme NuruMember \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/nuru-member-dd build

# Install + launch on a booted simulator
xcrun simctl install "iPhone 17" /tmp/nuru-member-dd/Build/Products/Debug-iphonesimulator/NuruMember.app
xcrun simctl launch "iPhone 17" org.nuruplace.member
```

Debug builds point at `http://localhost:8080/v1` (run the backend with
`pnpm --filter @nuru/backend dev` in the monorepo); Release builds point at prod.
Override with the `NURU_API_URL` launch environment variable.

### Sign in already authenticated (smoke test)

Debug builds honour `NURU_ACCESS_TOKEN` / `NURU_REFRESH_TOKEN` launch env vars to
start signed in — useful for screenshotting authed screens without typing a password.

## Layout

```
NuruMember/
├── NuruMemberApp.swift        ← @main entry, app chrome, splash
├── Theme/NuruTheme.swift      ← design tokens (port of mobile tokens.ts)
├── Networking/
│   ├── APIClient.swift        ← URLSession actor, single-flight 401 refresh
│   └── MemberAPI.swift        ← typed endpoint facade (port of NuruApi)
├── Auth/
│   ├── KeychainStore.swift    ← secure token vault (§5.7)
│   └── AuthStore.swift        ← session state, Login ↔ shell
├── Offline/OfflineStore.swift ← mutation queue + LocalStore + SyncEngine (§1.7)
├── Models/Models.swift        ← wire DTOs (mirror @nuru/shared)
├── Features/
│   ├── Login/                 ← LoginView (+ 2FA)
│   ├── Shell/                 ← RootView tab shell, Profile
│   ├── Home/                  ← HomeView (wired to /me, next-action, rhythm)
│   └── Shared/                ← Card, PButton, BrandMark, NuruField
└── Resources/Fonts/           ← Inter + Fraunces (OFL)
```
