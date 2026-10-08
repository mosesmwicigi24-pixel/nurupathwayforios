// My Prayer Room — the single destination that replaces the old separate
// "Prayer Wall" and "Prayer Journal" entries. FOUR tabs over one screen:
// Private Prayer (the member's own journal, PrayerJournalView, embedded),
// Corporate Prayer (the congregation's wall, PrayerWallView, embedded), Selah
// (My Thoughts — a private rich-text + pen journal, SelahView), and Prayer
// Points (the AI assist + corpus generator, PrayerPointsView). Child views
// keep their real behavior (compose, share-to-wall, react, comment, voice
// notes) — only their own header/back-button chrome is suppressed in favor of
// this screen's shared header + segmented control.
//
// "Answered" used to be its own top-level tab; it now folds into Private's
// own Active/Answered chips (PrayerJournalView already shows them whenever it
// isn't pinned to a forced tab) so the room stays at a clean four across —
// nothing about Answered itself was removed, just its top-level slot.
import SwiftUI

enum PrayerRoomTab: Hashable {
    case privatePrayer
    case corporatePrayer
    case selah
    case prayerPoints
}

struct PrayerRoomView: View {
    @State private var tab: PrayerRoomTab
    @Environment(\.dismiss) private var dismiss
    /// Community's "Pray" door: the room is a root there, not a pushed page —
    /// no back (the door row is the way out), and the bell at the right.
    let asDoor: Bool

    init(initialTab: PrayerRoomTab = .privatePrayer, asDoor: Bool = false) {
        _tab = State(initialValue: initialTab)
        self.asDoor = asDoor
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch tab {
                case .privatePrayer: PrayerJournalView(embedded: true)
                case .corporatePrayer: PrayerWallView(embedded: true)
                case .selah: SelahView()
                case .prayerPoints: PrayerPointsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // Cream Figma ScreenShell header (Prayer Journal's language): back ·
    // tracked kicker · serif title, with the Private/Corporate segmented
    // control anchored underneath.
    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            if asDoor {
                // One header (§8.1 rule 2): kicker · title · the bell.
                HStack(alignment: .top) {
                    NuruHeaderText(kicker: "Pray", title: "My Prayer Room")
                    Spacer(minLength: 0)
                    NuruBell()
                }
            } else {
            HStack(alignment: .center, spacing: Nuru.S.sm) {
                Button { dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: Nuru.navy)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Color.clear.frame(width: 40, height: 40) // balances the back button
            }
            // A pushed page: back · kicker · title (§8.1 rule 2) — the kicker
            // names where it lives, not the title again (the walk's 82:
            // "MY PRAYER ROOM · My Prayer Room").
            NuruHeaderText(kicker: "Pray", title: "My Prayer Room")
            }
            segmentedControl
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        // Under Community's door row there's no status bar to clear.
        .padding(.top, asDoor ? Nuru.S.base : 60)
        .padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.25)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
                .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
                .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: Segmented control (capsule pills, navy gradient active — Chat idiom)

    // Four tabs no longer fit one equal-width row on a phone, so the capsule
    // scrolls horizontally (iPad still shows all four at a glance); each pill
    // now sizes to its own label instead of splitting the strip evenly.
    private var segmentedControl: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                segmentButton(.privatePrayer, "Private")
                segmentButton(.corporatePrayer, "Corporate")
                segmentButton(.selah, "Selah")
                segmentButton(.prayerPoints, "Prayer Points")
            }
            .padding(4)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        }
    }

    private func segmentButton(_ t: PrayerRoomTab, _ label: String) -> some View {
        let selected = tab == t
        return Button {
            if !selected { Haptics.selection() }
            withAnimation(.easeInOut(duration: 0.15)) { tab = t }
        } label: {
            Text(label)
                .font(.nChipLabel)
                .foregroundStyle(selected ? Color.white : Color(hex: 0x59667C))
                .lineLimit(1).minimumScaleFactor(0.92)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    selected
                        ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.clear),
                    in: Capsule())
                .shadow(color: selected ? Color(hex: 0x0B1F33).opacity(0.35) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}
