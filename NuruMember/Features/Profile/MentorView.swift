// Mentorship — the native port of screens/MentorScreen.tsx. A navy rounded-bottom
// header over the member's real discipler pairing from GET /growth/mentor: the
// assigned discipler (avatar, cell, since-date), the next scheduled meeting, and
// the meeting-notes history. Falls back to an empty invite card when a leader
// hasn't paired the member with a discipler yet.
import SwiftUI

@MainActor
final class MentorViewModel: ObservableObject {
    @Published var info: MentorInfo?
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { info = try await MemberAPI.mentor() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your mentorship." }
        loading = false
    }
}

struct MentorView: View {
    @StateObject private var vm = MentorViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Nuru.S.base) {
                        if vm.loading && vm.info == nil {
                            ProgressView().tint(Nuru.gold).padding(.top, Nuru.S.xxl)
                        } else if let m = vm.info?.mentor {
                            disciplerCard(m)
                            if let next = vm.info?.nextMeetingAt { nextMeetingCard(next) }
                            notesSection
                        } else {
                            emptyCard
                        }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.info == nil { await vm.load() } }
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

    // MARK: Discipler card (avatar · name · cell · since)

    private func disciplerCard(_ m: MentorInfo.Mentor) -> some View {
        HStack(spacing: Nuru.S.base) {
            Avatar(url: m.avatarUrl, name: m.fullName, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.fullName).font(.inter(17, .bold)).foregroundStyle(Nuru.ink)
                if let cell = m.cellName {
                    Text(cell).font(.nCaption).foregroundStyle(Nuru.muted)
                }
                if let since = m.establishedAt.flatMap(Self.monthYear) {
                    Text("Walking with you since \(since)").font(.nMicro).foregroundStyle(Nuru.gold)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // MARK: Next meeting

    private func nextMeetingCard(_ iso: String) -> some View {
        HStack(spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).fill(Nuru.goldTint).frame(width: 44, height: 44)
                Icon(.calendarClock, size: 20, color: Nuru.gold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT MEETING").font(.inter(11, .semibold)).tracking(1.2).foregroundStyle(Nuru.gold)
                Text(Self.longDate(iso)).font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.priorityBg, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
    }

    // MARK: Meeting notes

    private var notesSection: some View {
        let notes = vm.info?.notes ?? []
        return VStack(alignment: .leading, spacing: Nuru.S.md) {
            if !notes.isEmpty {
                Text("MEETING NOTES").font(.inter(11, .bold)).tracking(1.2).foregroundStyle(Nuru.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(notes) { note in noteCard(note) }
            } else {
                Text("Your discipler's meeting notes will appear here after your first session.")
                    .font(.nCaption).foregroundStyle(Nuru.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func noteCard(_ note: MentorInfo.Note) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.topic?.isEmpty == false ? note.topic! : "Session")
                    .font(.inter(15, .bold)).foregroundStyle(Nuru.ink)
                Spacer(minLength: Nuru.S.sm)
                if let met = note.metAt.flatMap(Self.shortDate) {
                    Text(met).font(.nMicro).foregroundStyle(Nuru.gold)
                }
            }
            Text(note.note).font(.nBody).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let next = note.nextMeetingAt.flatMap(Self.shortDate) {
                Label("Next: \(next)", systemImage: "calendar")
                    .font(.nMicro).foregroundStyle(Nuru.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // MARK: Empty state (no pairing yet)

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

    // MARK: date helpers

    private static func parse(_ iso: String) -> Date? {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
    private static func monthYear(_ iso: String) -> String? {
        guard let d = parse(iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: d)
    }
    private static func longDate(_ iso: String) -> String {
        guard let d = parse(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d · h:mm a"; return f.string(from: d)
    }
    private static func shortDate(_ iso: String) -> String? {
        guard let d = parse(iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: d)
    }
}
