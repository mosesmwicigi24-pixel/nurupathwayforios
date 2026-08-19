// My attendance — the streak (current run, longest, breaks, failures) over a
// service-by-service history where MISSES are visible. Showing the misses is the
// point: a streak number alone doesn't tell a member which Sunday they lost.
//
// Port parity: Android AttendanceScreen.kt.
import SwiftUI

struct AttendanceView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AttendanceViewModel()
    @State private var showScanner = false

    var body: some View {
        ZStack {
            Nuru.navy.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Nuru.S.lg) {
                    header

                    // A service open right now is the most useful thing on this
                    // screen — surface it above the numbers so arriving members
                    // can act immediately.
                    if let open = vm.scannableService {
                        openServiceCard(open)
                    }

                    if let streak = vm.streak {
                        StreakSummary(streak: streak)
                    }

                    historySection
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.bottom, Nuru.S.xl)
            }
            .refreshable { await vm.load() }

            if vm.loading && vm.streak == nil {
                ProgressView().tint(Nuru.gold)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.streak == nil { await vm.load() } }
        .fullScreenCover(isPresented: $showScanner, onDismiss: { Task { await vm.load() } }) {
            ServiceCheckInView(memberName: vm.memberName,
                               memberPhone: vm.memberPhone,
                               memberEmail: vm.memberEmail)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CHURCH SERVICES")
                    .font(.inter(10, .bold)).kerning(1.6).foregroundStyle(Nuru.gold)
                Text("My attendance")
                    .font(.fraunces(26, .semibold)).kerning(-0.5).foregroundStyle(.white)
            }
            Spacer(minLength: Nuru.S.md)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                ZStack {
                    Circle().fill(Color.white.opacity(0.12)).frame(width: 36, height: 36)
                    Icon(.x, size: 17, color: .white)
                }
            }
            .buttonStyle(.pressable)
        }
        .padding(.top, Nuru.S.lg)
    }

    private func openServiceCard(_ service: ChurchService) -> some View {
        Button {
            Haptics.tap()
            showScanner = true
        } label: {
            HStack(spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Nuru.goldGradient).frame(width: 48, height: 48)
                    Icon(.qrCode, size: 22, color: Nuru.navy)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("OPEN NOW").font(.inter(9, .bold)).kerning(1.5).foregroundStyle(Nuru.goldLight)
                    Text(service.title).font(.nRowTitle).foregroundStyle(Nuru.onNavy)
                    Text("Scan the QR at church to check in")
                        .font(.nCardMeta).foregroundStyle(Nuru.onNavyDim)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 18, color: .white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .padding(Nuru.S.base)
            .background(Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.pressableSubtle)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            Text("SERVICE BY SERVICE")
                .font(.inter(10, .bold)).kerning(1.6).foregroundStyle(Nuru.gold)

            if let error = vm.error {
                Text(error).font(.inter(13)).foregroundStyle(Nuru.goldLight)
            } else if vm.history.isEmpty && !vm.loading {
                Text("No services yet. Scan the QR at church and your record starts.")
                    .font(.inter(13)).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(vm.history) { entry in
                    HistoryRow(entry: entry)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: AttendanceHistoryEntry

    var body: some View {
        HStack(spacing: Nuru.S.md) {
            // Gold dot = present, hollow = a miss. Legible at a glance down the column.
            Group {
                if entry.attended {
                    Circle().fill(Nuru.gold)
                } else {
                    Circle().stroke(Color.white.opacity(0.35), lineWidth: 1)
                }
            }
            .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.nRowTitle).foregroundStyle(Nuru.onNavy)
                Text(entry.serviceDate).font(.nCardMeta).foregroundStyle(Nuru.onNavyDim)
            }
            Spacer(minLength: 0)
            Text(entry.attended ? (entry.attendedAt.map(shortTime) ?? "Present") : "Missed")
                .font(.inter(12))
                .foregroundStyle(entry.attended ? Nuru.gold : Color.white.opacity(0.4))
        }
        .padding(Nuru.S.md)
        .background(Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

@MainActor
final class AttendanceViewModel: ObservableObject {
    @Published var streak: AttendanceStreak?
    @Published var history: [AttendanceHistoryEntry] = []
    @Published var openServices: [ChurchService] = []
    @Published var loading = false
    @Published var error: String?

    // Prefill for the check-in form. Loaded here rather than threaded through
    // navigation so the screen (and the scanner it presents) is self-sufficient.
    @Published var memberName = ""
    @Published var memberPhone = ""
    @Published var memberEmail: String?

    /// The one service worth offering a scan for: open, and not already attended.
    var scannableService: ChurchService? {
        openServices.first { $0.checkinOpen && !$0.attended }
    }

    func load() async {
        loading = true
        error = nil
        do {
            async let s = MemberAPI.attendanceStreak()
            async let h = MemberAPI.attendanceHistory()
            async let o = MemberAPI.openServices()
            streak = try await s
            history = try await h
            openServices = try await o
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your attendance."
        }
        // The profile is only a form prefill — a failure here must not block the
        // screen, and the server falls back to the profile server-side anyway.
        if let profile = try? await MemberAPI.me().profile {
            memberName = profile.fullName
            memberPhone = profile.phoneNumber ?? ""
            memberEmail = profile.email
        }
        loading = false
    }
}
