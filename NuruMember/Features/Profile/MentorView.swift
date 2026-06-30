// Mentorship — the native port of screens/MentorScreen.tsx (empty state). A navy
// rounded-bottom header (circular back button, gold overline, serif title) over a
// single white card inviting the member to wait for a leader-assigned discipler.
// Static for now; meetings + notes land once a pairing exists (later pass).
import SwiftUI

struct MentorView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Nuru.S.base) {
                        emptyCard
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // Navy header with a rounded bottom, circular back button, gold overline and serif title.
    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.onNavy)
                    .frame(width: 38, height: 38)
                    .background(Nuru.navyDeep, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("YOUR DISCIPLER")
                    .font(.inter(11, .bold)).tracking(1.4)
                    .foregroundStyle(Nuru.gold)
                Text("Mentorship")
                    .font(.fraunces(26, .semibold))
                    .foregroundStyle(Nuru.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.sm)
        .padding(.bottom, Nuru.S.lg)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous)
                .fill(Nuru.navy)
                .ignoresSafeArea(edges: .top)
        )
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                    .fill(Nuru.goldTint)
                    .frame(width: 48, height: 48)
                Icon(.heartHandshake, size: 22, color: Nuru.gold)
            }
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("No discipler yet")
                    .font(.inter(17, .bold))
                    .foregroundStyle(Nuru.ink)
                Text("When your leader pairs you with a discipler, you'll see your meetings and notes here.")
                    .font(.nCaption)
                    .foregroundStyle(Nuru.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous)
                .stroke(Nuru.border, lineWidth: 1)
        )
        .nuruShadow()
    }
}
