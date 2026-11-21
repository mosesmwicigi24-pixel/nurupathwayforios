// How the reading screens are lit (member suggestion, 2026-11-21: "dark mode
// would be particularly useful for reading at night"). The four readers — a
// plan's part, today's devotional, the Sunday letter and a Pathway lesson —
// each have a warm day page and the readers' dark sepia night page
// (ReaderPalette's); this is the member's choice between them, made in
// Settings → Display or with the moon/sun button on any reader, and kept on
// this phone. Automatic, the default, follows the phone's own dark mode.
//
// App-wide dark mode is out of scope: NuruMemberApp keeps the whole app in
// `.preferredColorScheme(.light)`, so inside it `@Environment(\.colorScheme)`
// always says light. Automatic therefore reads the SYSTEM's style from the
// screen's own trait collection (which the app's override doesn't reach),
// refreshed whenever the app becomes active — the moment a member who just
// switched dark mode in Control Centre or Settings comes back — and whenever
// a reader opens. Android's twin: data/ReadingTheme.kt.
import SwiftUI
import UIKit

enum ReadingTheme: String, CaseIterable, Identifiable {
    case auto, day, night

    /// Where the choice is kept (Android's AppPrefs key, the same name).
    static let storageKey = "nuru.readingTheme"
    /// The plan reader's old on/off switch, before there was a choice of three.
    static let legacyNightKey = "readerNight"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .day: return "Day"
        case .night: return "Night"
        }
    }

    var icon: Lucide {
        switch self {
        case .auto: return .smartphone
        case .day: return .sun
        case .night: return .moon
        }
    }

    /// Whether the readers draw their night page, given the phone's own style.
    func isNight(systemDark: Bool) -> Bool {
        switch self {
        case .auto: return systemDark
        case .day: return false
        case .night: return true
        }
    }

    /// An unknown or missing key is Automatic.
    static func from(_ key: String?) -> ReadingTheme {
        guard let key, let theme = ReadingTheme(rawValue: key) else { return .auto }
        return theme
    }

    /// A reader's moon/sun button: the OTHER page, chosen explicitly — so a
    /// tap on an Automatic night page gives Day, and Settings then says Day.
    static func toggled(currentlyNight: Bool) -> ReadingTheme {
        currentlyNight ? .day : .night
    }

    /// What the moon/sun button says it does.
    static func toggleLabel(night: Bool) -> String {
        night ? "Day page" : "Night page"
    }

    /// The value to store for a member upgrading from the plan reader's old
    /// switch: a member who read at night keeps reading at night. Nil when
    /// there is nothing to carry over (a choice already made, or no night).
    static func migratedValue(stored: String?, legacyNight: Bool) -> String? {
        guard stored == nil, legacyNight else { return nil }
        return ReadingTheme.night.rawValue
    }

    /// Run once at launch (NuruMemberApp), before any reader reads the key.
    static func migrateLegacySetting(in defaults: UserDefaults = .standard) {
        let stored = defaults.string(forKey: storageKey)
        if let value = migratedValue(stored: stored, legacyNight: defaults.bool(forKey: legacyNightKey)) {
            defaults.set(value, forKey: storageKey)
        }
    }
}

/// Settings → Display's words for the choice (Android's SettingsScreen).
enum ReadingThemeWords {
    static let title = "Reading theme"
    static let caption = "Plans, the devotional, the Sunday letter and lessons. Automatic follows your phone's dark mode. Each reader has a listen button too."
}

/// The phone's own light/dark style, for Automatic. A reader observes it
/// (`@ObservedObject … = ReadingAppearance.shared`) beside its
/// `@AppStorage(ReadingTheme.storageKey)`, so a change to either redraws it.
@MainActor
final class ReadingAppearance: ObservableObject {
    static let shared = ReadingAppearance()

    @Published private(set) var systemDark = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        systemDark = Self.systemIsDark()
        let names: [Notification.Name] = [UIApplication.didBecomeActiveNotification,
                                          UIApplication.willEnterForegroundNotification]
        for name in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            observers.append(token)
        }
    }

    /// Read the system's style again (a reader calls this as it opens).
    func refresh() {
        let dark = Self.systemIsDark()
        if dark != systemDark { systemDark = dark }
    }

    /// The SCREEN's trait collection: the system's style, which the window's
    /// light override (NuruMemberApp) doesn't touch.
    static func systemIsDark() -> Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let traits: UITraitCollection = scene?.screen.traitCollection ?? UIScreen.main.traitCollection
        return traits.userInterfaceStyle == .dark
    }
}
