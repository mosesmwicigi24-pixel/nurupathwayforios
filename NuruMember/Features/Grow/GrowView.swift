// Grow — the daily-rhythm & Word hub. A native home for the screens the RN app
// reached from Home and the "Plans" tab: today's Devotional, Memory Verses,
// Reading Plans, the Prayer Journal and the Verse Library. Hosts the navigation
// stack for all of them.
import SwiftUI

enum GrowRoute: Hashable {
    case devotional
    case memoryVerses
    case plans
    case prayer
    case verses
}

struct GrowView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Nuru.paper.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Nuru.S.md) {
                        row(.devotional, "Today's Devotional", "Read and reflect", "sun.max.fill")
                        row(.memoryVerses, "Memory Verses", "Hide the Word in your heart", "text.book.closed.fill")
                        row(.plans, "Reading Plans", "Guided journeys through Scripture", "list.bullet.rectangle.fill")
                        row(.prayer, "Prayer Journal", "Your private prayers", "hands.sparkles.fill")
                        row(.verses, "Verse Library", "Verses you've saved", "bookmark.fill")
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
            .navigationTitle("Grow")
            .navigationDestination(for: GrowRoute.self) { route in
                switch route {
                case .devotional:   DevotionalView()
                case .memoryVerses: MemoryVerseView()
                case .plans:        ReadingPlansView()
                case .prayer:       PrayerJournalView()
                case .verses:       VerseLibraryView()
                }
            }
            .navigationDestination(for: ReadingPlanRow.self) { PlanDetailView(plan: $0) }
            .navigationDestination(for: PlanDayRef.self) { PlanDayView(ref: $0) }
        }
    }

    private func row(_ route: GrowRoute, _ title: String, _ subtitle: String, _ icon: String) -> some View {
        NavigationLink(value: route) {
            Card {
                HStack(spacing: Nuru.S.base) {
                    ZStack {
                        Circle().fill(Nuru.goldTint).frame(width: 44, height: 44)
                        Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Nuru.gold)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.nHeading).foregroundStyle(Nuru.ink)
                        Text(subtitle).font(.nCaption).foregroundStyle(Nuru.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Nuru.ink300)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small shared helpers for Grow screens

/// A standard loading / empty / error scaffold so each Grow screen stays terse.
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
