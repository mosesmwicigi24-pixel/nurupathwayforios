// The Sunday Letter — a weekly pastoral letter written from the member's
// ACTUAL week (lessons finished, reflections, answered prayers), composed
// server-side by the intelligence layer and presented as warm stationery:
// cream paper, serif voice, a scripture pill, and the gold Nuru seal.
import SwiftUI

struct LetterView: View {
    let letter: PastoralLetter
    var onRead: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    private var weekLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: letter.weekOf) else { return letter.weekOf }
        let out = DateFormatter()
        out.dateFormat = "d MMMM yyyy"
        return out.string(from: d)
    }

    var body: some View {
        ZStack {
            // Deep navy backdrop lets the paper glow.
            LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x081020)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    seal.padding(.top, 34).padding(.bottom, -34).zIndex(1)
                    paper
                        .padding(.horizontal, 22)
                        .padding(.bottom, 30)
                }
                .padding(.top, 26)
            }

            // Close
            VStack {
                HStack {
                    Spacer()
                    Button {
                        Haptics.tap(); dismiss()
                    } label: {
                        Icon(.x, size: 15, color: .white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .padding(.trailing, 18)
                }
                Spacer()
            }
            .padding(.top, 14)
        }
        .onAppear {
            guard letter.isUnread else { return }
            Task { _ = try? await MemberAPI.markLetterRead(letter.letterId); onRead() }
        }
    }

    /// Gold wax seal with the Nuru mark, overlapping the paper's top edge.
    private var seal: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0xE8CA6C), Color(hex: 0xB6862F)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 68, height: 68)
                .shadow(color: Color(hex: 0xC9A227).opacity(0.5), radius: 12, y: 5)
            Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5).frame(width: 54, height: 54)
            Text("N").font(.fraunces(30, .semibold)).foregroundStyle(Color(hex: 0x1E2A1F))
        }
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("THE SUNDAY LETTER").font(.inter(10, .bold)).kerning(2.0)
                    .foregroundStyle(Color(hex: 0xA8861C))
                Text("Week of \(weekLabel)").font(.inter(12)).foregroundStyle(Color(hex: 0x74808F))
            }
            .padding(.top, 44)

            if let ref = letter.scriptureRef {
                HStack(spacing: 7) {
                    Icon(.bookOpen, size: 13, color: Color(hex: 0xA8861C))
                    Text(ref).font(.inter(12, .bold)).foregroundStyle(Color(hex: 0x8A6B1F))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color(hex: 0xFDF5E5), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: 0xF2E2BD), lineWidth: 1))
            }

            Text(letter.body)
                .font(.fraunces(17, .regular))
                .foregroundStyle(Color(hex: 0x2A3441))
                .nuruLineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                ShareLink(item: "\(letter.scriptureRef.map { "📖 \($0)\n\n" } ?? "")\(letter.body)") {
                    HStack(spacing: 6) {
                        Icon(.share2, size: 14, color: Color(hex: 0x8A6B1F))
                        Text("Share").font(.inter(12, .bold)).foregroundStyle(Color(hex: 0x8A6B1F))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(hex: 0xFDF5E5), in: Capsule())
                }
            }
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 24).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0xFFFDF6), Color(hex: 0xF8F3E6)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color(hex: 0xC9A227).opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }
}
