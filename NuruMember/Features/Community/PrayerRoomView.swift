// My Prayer Room — the single destination that replaces the old separate
// "Prayer Wall" and "Prayer Journal" entries. Two tabs over one screen:
// Private Prayer (the member's own journal, PrayerJournalView, embedded) and
// Corporate Prayer (the congregation's wall, PrayerWallView, embedded). Both
// child views keep their real behavior (compose, share-to-wall, react,
// comment, voice notes) — only their own header/back-button chrome is
// suppressed in favor of this screen's shared header + segmented control.
import SwiftUI

enum PrayerRoomTab: Hashable {
    case privatePrayer
    case corporatePrayer
}

struct PrayerRoomView: View {
    @State private var tab: PrayerRoomTab
    @Environment(\.dismiss) private var dismiss

    init(initialTab: PrayerRoomTab = .privatePrayer) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch tab {
                case .privatePrayer: PrayerJournalView(embedded: true)
                case .corporatePrayer: PrayerWallView(embedded: true)
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
            HStack(alignment: .center, spacing: Nuru.S.sm) {
                Button { dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: Nuru.navy)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text("MY PRAYER ROOM")
                    .font(.inter(11, .bold)).tracking(1.8)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Color.clear.frame(width: 40, height: 40) // balances the back button
            }
            Text("My Prayer Room")
                .font(.fraunces(24, .semibold))
                .foregroundStyle(Nuru.navy)
            segmentedControl
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 60)
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

    private var segmentedControl: some View {
        HStack(spacing: 4) {
            segmentButton(.privatePrayer, "Private Prayer")
            segmentButton(.corporatePrayer, "Corporate Prayer")
        }
        .padding(4)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    private func segmentButton(_ t: PrayerRoomTab, _ label: String) -> some View {
        let selected = tab == t
        return Button {
            if !selected { Haptics.selection() }
            withAnimation(.easeInOut(duration: 0.15)) { tab = t }
        } label: {
            Text(label)
                .font(.inter(12, .semibold))
                .foregroundStyle(selected ? Color.white : Color(hex: 0x59667C))
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
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
