// Wave 1 — the echo card: the app remembers you.
// One moment per day, server-chosen from the member's own history: their
// reflection words carried back, a grace-first welcome after quiet days, or
// a month-anniversary of a finished module. Renders nothing when the server
// has nothing true and specific to say.
import SwiftUI

struct HomeEchoCard: View {
    @State private var echo: HomeEcho?

    private var kicker: String {
        switch echo?.kind {
        case "welcome_back": return "WELCOME BACK"
        case "anniversary": return "REMEMBER THIS DAY"
        default: return "NURU REMEMBERS"
        }
    }

    var body: some View {
        Group {
            if let e = echo {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Icon(.sparkles, size: 13, color: Nuru.goldChipText)
                        Text(kicker)
                            .font(.inter(10.5, .bold)).kerning(1.6)
                            .foregroundStyle(Nuru.goldChipText)
                        Spacer()
                    }
                    Text(e.body)
                        .font(.inter(14.5)).foregroundStyle(Nuru.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if let q = e.quote, !q.isEmpty {
                        Text("\u{201C}\(q)\u{201D}")
                            .font(.fraunces(16)).italic().foregroundStyle(Nuru.navyMid)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 12)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(Nuru.gold).frame(width: 3)
                            }
                    }
                    if let r = e.ref, !r.isEmpty {
                        Text("— \(r)")
                            .font(.inter(11.5, .semibold)).foregroundStyle(Nuru.goldChipText)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
            }
        }
        .task { echo = try? await MemberAPI.homeEcho() }
    }
}
