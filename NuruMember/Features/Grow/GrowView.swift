// Shared navigation destinations + small load-state helper for the member app.
// The growth screens (Devotional, Memory Verses, Reading Plans, Prayer Journal,
// Verse Library) are reached from Home's "Grow your faith" grid and the Plans
// tab — exactly like the RN app, which has no separate "Grow" tab.
import SwiftUI

/// Value-routes for the growth screens, pushed from Home / Plans stacks.
enum GrowDestination: Hashable {
    case devotional
    case memoryVerses
    case readingPlans
    case prayerJournal
    case verseLibrary
    case gifts
    case resources
}

extension View {
    /// Registers every cross-screen navigation destination so any stack (Home,
    /// Plans, Community) can push the same screens with value-based links.
    func nuruDestinations() -> some View {
        self
            .navigationDestination(for: GrowDestination.self) { d in
                switch d {
                case .devotional:    DevotionalView()
                case .memoryVerses:  MemoryVerseView()
                case .readingPlans:  ReadingPlansView()
                case .prayerJournal: PrayerJournalView()
                case .verseLibrary:  VerseLibraryView()
                case .gifts:         PlaceholderScreen(title: "Your Calling", blurb: "Discover your spiritual gifts.", icon: .sparkles)
                case .resources:     PlaceholderScreen(title: "Resources", blurb: "Books, audio and teaching.", icon: .bookOpen)
                }
            }
            .navigationDestination(for: ReadingPlanRow.self) { PlanDetailView(plan: $0) }
            .navigationDestination(for: PlanDayRef.self) { PlanDayView(ref: $0) }
            .navigationDestination(for: CommunityRoute.self) { r in
                switch r {
                case .prayerWall: PrayerWallView()
                case .prayer(let id): PrayerWallDetailView(postId: id)
                }
            }
            .navigationDestination(for: PathwayRoute.self) { r in
                switch r {
                case .level(let n): LevelDetailView(levelNumber: n)
                case .module(let id): ModuleView(moduleId: id)
                case .quiz(let id): QuizView(moduleId: id)
                }
            }
    }
}

/// A standard loading / empty / error scaffold so each data screen stays terse.
struct LoadStateView<Content: View>: View {
    let loading: Bool
    let isEmpty: Bool
    let error: String?
    let emptyText: String
    let retry: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        if loading {
            ProgressView()
        } else if let error, isEmpty {
            VStack(spacing: Nuru.S.md) {
                Text(error).font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
                Button("Try again", action: retry).font(.inter(14, .semibold)).foregroundStyle(Nuru.gold)
            }
            .padding(Nuru.S.xl)
        } else if isEmpty {
            Text(emptyText).font(.nBody).foregroundStyle(Nuru.muted).padding(Nuru.S.xl)
        } else {
            content()
        }
    }
}

/// A simple branded placeholder for screens not yet ported.
struct PlaceholderScreen: View {
    var title: String
    var blurb: String
    var icon: Lucide

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: Nuru.S.base) {
                Icon(icon, size: 40, color: Nuru.gold)
                Text(title).font(.fraunces(22, .semibold)).foregroundStyle(Nuru.ink)
                Text(blurb).font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
                Text("Coming soon").font(.nMicro).foregroundStyle(Nuru.faint)
            }
            .padding(Nuru.S.xl)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
