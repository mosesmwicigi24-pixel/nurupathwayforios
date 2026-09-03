// The partner invitation — the one place the app asks for money unprompted.
//
// THIS VIEW DECIDES NOTHING. Whether to ask is settled entirely on the server
// (invitation.ts): never a partner, never a minor, never someone's first week,
// never in their quiet hours, three showings per campaign, a fortnight between
// waves. Duplicating any of that here is how the two apps drift, and the drift
// is always towards asking more often. This asks, renders, and reports back.
//
// Three deliberate restraints in the presentation itself:
//
//   · the primary button opens the Partners page, NOT a payment sheet. Nobody
//     should be one tap from a charge they have not read about.
//   · dismissal is always available and never punished — swipe, backdrop, or
//     Not now. On a second showing "Don't ask again" appears, because someone
//     who has said no twice deserves a way to end it.
//   · a match is rendered only when the payload carries a pledger. The server
//     and the database both refuse an unpledged match; this is the third gate.
import SwiftUI

struct PartnerInviteSheet: View {
    let campaign: PartnerInvite.Campaign
    /// Higher on a repeat showing — that is when "don't ask again" appears.
    let showing: Int
    let onBecomePartner: () -> Void
    let onDismiss: (_ permanent: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 18) {
                    Text(campaign.title)
                        .font(.nuruDisplay(27)).foregroundStyle(Nuru.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(campaign.blurb)
                        .font(.nBodyLg).foregroundStyle(Nuru.ink600)
                        .fixedSize(horizontal: false, vertical: true)

                    progress
                    if let m = campaign.match { matchNote(m) }
                    tiers
                    actions
                }
                .padding(20)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    // MARK: - Photograph

    @ViewBuilder private var header: some View {
        if let url = campaign.imageUrl, let u = URL(string: url) {
            CachedAsyncImage(url: u) { phase in
                if case .success(let img) = phase {
                    HomeFadeInImage(image: img)
                } else {
                    Rectangle().fill(Nuru.navy.opacity(0.06))
                }
            }
            .frame(height: 190).frame(maxWidth: .infinity)
            .clipped()
        }
    }

    // MARK: - Where the goal really stands

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Nuru.navy.opacity(0.10))
                    Capsule().fill(Nuru.gold)
                        .frame(width: max(4, geo.size.width * campaign.progress))
                }
            }
            .frame(height: 7)

            HStack(spacing: 6) {
                Text("\(campaign.currency) \(InviteFormat.grouped(campaign.raisedMinor / 100))")
                    .font(.nLabel).foregroundStyle(Nuru.ink)
                Text("of \(campaign.currency) \(InviteFormat.grouped(campaign.goalMinor / 100))")
                    .font(.nCaption).foregroundStyle(Nuru.ink600)
                Spacer(minLength: 8)
                // Honest about time without manufacturing panic.
                Text(daysPhrase).font(.nCaption).foregroundStyle(Nuru.ink600)
            }
        }
    }

    private var daysPhrase: String {
        switch campaign.daysLeft {
        case 0: "Ends today"
        case 1: "1 day left"
        default: "\(campaign.daysLeft) days left"
        }
    }

    // MARK: - A match, only when someone really pledged one

    private func matchNote(_ m: PartnerInvite.Match) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13)).foregroundStyle(Nuru.goldLo)
                .padding(.top, 2)
            // The pledger is NAMED. An unnamed match is the kind of claim this
            // whole design exists to prevent.
            Text("\(m.pledger) will match every gift up to \(campaign.currency) \(InviteFormat.grouped(m.amountMinor / 100)).")
                .font(.nBody).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Amounts that mean something

    private var tiers: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(campaign.tiers) { t in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(t.currency) \(InviteFormat.grouped(t.amountMinor / 100))")
                        .font(.nuruDisplay(19)).foregroundStyle(Nuru.ink)
                        .frame(minWidth: 96, alignment: .leading)
                    // The meaning comes from the server, derived from one
                    // costing. Never invented here.
                    Text(t.meaning)
                        .font(.nCaption).foregroundStyle(Nuru.ink600)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Nuru.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            Text("A monthly gift. Change it or stop it whenever you need to.")
                .font(.nCaption).foregroundStyle(Nuru.ink400)
                .padding(.top, 2)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            // Opens the Partners page, NOT a payment sheet.
            Button {
                onBecomePartner(); dismiss()
            } label: {
                Text("Become a partner")
                    .font(.nHeading)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Nuru.navyDeep, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }

            Button { onDismiss(false); dismiss() } label: {
                Text("Not now").font(.nBody).foregroundStyle(Nuru.ink600)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }

            // Only from the second showing. Offering it immediately invites a
            // permanent no from someone who simply had a busy morning.
            if showing >= 2 {
                Button { onDismiss(true); dismiss() } label: {
                    Text("Don't ask again").font(.nCaption).foregroundStyle(Nuru.ink400)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 4)
    }
}

enum InviteFormat {
    private static let n: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f
    }()
    static func grouped(_ v: Int) -> String { n.string(from: NSNumber(value: v)) ?? "\(v)" }
}
