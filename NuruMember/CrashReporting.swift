// Crash-reporting bring-up — Firebase Crashlytics, wired the same way Android
// gets it (same Firebase project, for a consistent incident story across
// surfaces). This repo had ZERO Firebase wiring before this file.
//
// SAFETY: naively calling `FirebaseApp.configure()` when no valid
// GoogleService-Info.plist is present makes Firebase itself `fatalError()`
// at launch — the opposite of what a crash *reporter* should ever do. So we
// never call the parameterless `configure()`. Instead we build our own
// `FirebaseOptions` from the plist and only hand it to Firebase once that
// succeeds. Until the real plist is added, this is a silent no-op and the
// rest of the app runs exactly as it does today.
//
// Native coverage: unlike Android (which needs the separate NDK Crashlytics
// step to see C/C++ crashes), iOS Crashlytics captures native crashes
// (C/C++/Objective-C — including WebRTC, tonight's actual incident) as part
// of the standard SDK. No extra configuration is needed for that once this
// is wired up.
//
// PRIVACY: this is a discipleship app holding pastoral data (prayer,
// reflections, chat, letters). We never call a Crashlytics user-ID API, and
// we never attach member content as a custom key/breadcrumb. If breadcrumbs
// are ever added here, they must stay non-content identifiers only (e.g. a
// screen/feature name) — never message, prayer, reflection, or letter text.
import FirebaseCore
import FirebaseCrashlytics
import Foundation
import os

private let crashLogger = Logger(subsystem: "org.nuruplace.member", category: "CrashReporting")

enum CrashReporting {
    /// Call once at launch, before anything else. Safe to call even when the
    /// project has no `GoogleService-Info.plist` at all (today's state) — it
    /// logs once via `os.Logger` (never via Crashlytics, which isn't up yet)
    /// and returns without touching Firebase.
    static func configureIfAvailable() {
        guard
            let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let options = FirebaseOptions(contentsOfFile: plistPath)
        else {
            crashLogger.notice(
                "GoogleService-Info.plist missing or invalid — Crashlytics stays off. Expected until the real Firebase config (project pathway-63ca4, bundle org.nuruplace.member) is added."
            )
            return
        }
        FirebaseApp.configure(options: options)
        crashLogger.notice("Crashlytics configured.")
    }
}
