// The watch's pulse and its invitation.
//
// EkklesiaPulse: one small summary (GET /ekklesia/summary) shared by the Home
// card and every invitation, so four pages never ask four times. Read once a
// minute at most; any Ekklesia write invalidates it.
//
// EkklesiaInvite: one quiet row, placed on a few pages (the Pathway, Plans,
// Events) and never twice on one. A member who is not on the watch reads the
// day's line and a gold "Join"; an intercessor reads the watch's real count
// for them today. Nothing shows until the watch has answered once.
import SwiftUI

@MainActor
final class EkklesiaPulse: ObservableObject {
    static let shared = EkklesiaPulse()
    @Published var summary: EkklesiaSummary?
    private var loadedAt: Date = .distantPast
    private let fresh: TimeInterval = 60

    /// Loads when stale; a failure keeps whatever was last known.
    func refresh(force: Bool = false) async {
        if !force, summary != nil, Date().timeIntervalSince(loadedAt) < fresh { return }
        if let s = try? await MemberAPI.ekklesiaSummary() { summary = s; loadedAt = Date() }
    }

    /// After a join, a leave, a need brought or an intercession.
    func invalidate() { loadedAt = .distantPast }

    /// On sign-out: the next member starts with no one else's watch.
    func clear() { summary = nil; loadedAt = .distantPast }
}

struct EkklesiaInvite: View {
    @ObservedObject private var pulse = EkklesiaPulse.shared
    @EnvironmentObject private var tabs: TabRouter

    var body: some View {
        Group {
            if let s = pulse.summary {
                Button {
                    Haptics.tap()
                    tabs.openEkklesia()
                } label: {
                    row(s)
                }
                .buttonStyle(.pressableSubtle)
            }
        }
        .task { await pulse.refresh() }
    }

    private func row(_ s: EkklesiaSummary) -> some View {
        let member = s.isMember
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(member ? Nuru.gold.opacity(0.18) : Color.white).frame(width: 36, height: 36)
                Icon(.flame, size: 18, color: member ? Nuru.gold : Nuru.navy)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(member ? "EKKLESIA · THE WATCH" : "EKKLESIA · INTERCESSORS")
                    .font(.inter(10, .semibold)).kerning(1.6)
                    .foregroundStyle(member ? Nuru.gold : Nuru.goldChipText)
                Text(member ? EkklesiaWords.memberLine(needsMeToday: s.needsMeToday, urgent: s.urgentCount)
                            : EkklesiaWords.invitation(dayOfYear: Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0))
                    .font(.inter(13, .medium))
                    .foregroundStyle(member ? Color.white : Nuru.navy)
                    .multilineTextAlignment(.leading)
                if !member, let under = EkklesiaWords.standing(memberCount: s.memberCount) {
                    Text(under).font(.inter(11, .regular)).foregroundStyle(Nuru.ink600)
                }
            }
            Spacer(minLength: 0)
            Text(member ? "Intercede ›" : "Join ›").font(.inter(12, .bold)).foregroundStyle(member ? Nuru.gold : Nuru.navy)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: member
                    ? [Color(hex: 0x0A1628), Color(hex: 0x16273F)]
                    : [Nuru.goldTint.opacity(0.55), Nuru.goldTint.opacity(0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(member ? Color.white.opacity(0.10) : Nuru.gold.opacity(0.30), lineWidth: 1))
    }
}

/// A face on the watch — the avatar when there is one, initials otherwise.
struct EkklesiaFaceView: View {
    let name: String
    let url: String?
    var size: CGFloat = 32
    var ring: Bool = false
    var body: some View {
        ZStack {
            Circle().fill(Nuru.goldChipBg)
            if let url, !url.isEmpty, let u = URL(string: url) {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(ring ? Color(hex: 0x0E1D33) : .clear, lineWidth: 1.5))
    }
    private var initials: some View {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }
        return Text(parts.isEmpty ? "?" : parts.joined().uppercased())
            .font(.inter(size * 0.36, .semibold)).foregroundStyle(Nuru.navy)
    }
}
