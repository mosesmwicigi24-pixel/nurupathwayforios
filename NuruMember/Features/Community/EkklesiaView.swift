// Ekklesia — the intercessory watch, the Prayer Room's fifth tab. The watch
// itself at the top (who stands, what waits, join or leave), then the needs:
// bodies and the act of interceding for intercessors; titles only, and the
// door in, for everyone else. Any member may bring a need. Android parity:
// EkklesiaScreen.kt (same strings, same order).
import SwiftUI

@MainActor
final class EkklesiaViewModel: ObservableObject {
    @Published var overview: EkklesiaOverview?
    @Published var status = "active"
    @Published var loading = true
    @Published var failure: Error?

    func load() async {
        loading = true; failure = nil
        do { overview = try await MemberAPI.ekklesia(status: status) } catch { failure = error }
        loading = false
    }
    func setStatus(_ s: String) async {
        guard s != status else { return }
        status = s; await load()
    }
    /// Any write: the watch re-reads itself and the pulse the Home card reads.
    func after(_ work: () async throws -> Void) async {
        do { try await work() } catch { failure = error }
        EkklesiaPulse.shared.invalidate()
        await load()
        await EkklesiaPulse.shared.refresh(force: true)
    }
}

struct EkklesiaView: View {
    @StateObject private var vm = EkklesiaViewModel()
    @State private var composing = false
    @State private var leaveArmed = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if let ov = vm.overview {
                    watchCard(ov.group)
                    bringPrompt
                    HStack(spacing: 8) {
                        statusPill("Active", ov.group.activeCount, on: vm.status == "active") { Task { await vm.setStatus("active") } }
                        statusPill("Answered", ov.group.answeredCount, on: vm.status == "answered") { Task { await vm.setStatus("answered") } }
                    }
                    if !ov.group.isMember {
                        if ov.preview.isEmpty {
                            NuruStateView(state: .empty(
                                title: vm.status == "answered" ? "No answered needs yet" : "The watch is quiet",
                                line: vm.status == "answered" ? "When a need closes with a testimony, it rests here." : "Bring a need, or stand ready for the next one."))
                        } else {
                            ForEach(ov.preview) { previewCard($0) }
                            Text("Join the watch to read each need and intercede. Only intercessors see what is written.")
                                .font(.inter(12, .regular)).foregroundStyle(Nuru.ink400).padding(.horizontal, 4)
                        }
                    } else if ov.requests.isEmpty {
                        NuruStateView(state: .empty(
                            title: vm.status == "answered" ? "No answered needs yet" : "Nothing waits on the watch",
                            line: vm.status == "answered" ? "When a need closes with a testimony, it rests here." : "The first need brought here will reach every intercessor at once."))
                    } else {
                        ForEach(ov.requests) { r in
                            NavigationLink(value: CommunityRoute.ekklesiaRequest(r.requestId)) {
                                EkklesiaRequestCard(r) { Task { await vm.after { try await MemberAPI.ekklesiaIntercede(r.requestId) } } }
                            }
                            .buttonStyle(.pressableSubtle)
                        }
                    }
                } else if vm.loading {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white).frame(height: 120).gentleEntrance(delay: Double(i) * 0.08)
                    }
                } else if let f = vm.failure {
                    NuruStateView(state: .failed(.failure(f)), retry: { Task { await vm.load() } })
                }
            }
            .padding(.horizontal, Nuru.S.screen).padding(.top, Nuru.S.lg).padding(.bottom, 32)
        }
        .background(Nuru.paper)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $composing) {
            EkklesiaBringSheet { Task { await vm.after {} } }
        }
    }

    // MARK: the watch

    private func watchCard(_ g: EkklesiaGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EKKLESIA · INTERCESSORS").font(.inter(11, .semibold)).kerning(1.8).foregroundStyle(Nuru.gold)
                    Text(g.mission).font(.fraunces(22, .semibold)).foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                ZStack { Circle().fill(Nuru.gold.opacity(0.16)).frame(width: 44, height: 44); Icon(.flame, size: 22, color: Nuru.gold) }
            }
            Text("The church on its knees for the church. A need brought here reaches every intercessor, and is prayed again tomorrow.")
                .font(.inter(12, .regular)).foregroundStyle(.white.opacity(0.72)).lineSpacing(3)
            HStack(spacing: 10) {
                if g.memberCount > 0 { stat(g.memberCount, g.memberCount == 1 ? "intercessor" : "intercessors") }
                if g.activeCount > 0 { stat(g.activeCount, g.activeCount == 1 ? "need" : "needs") }
                if g.prayersToday > 0 { stat(g.prayersToday, "prayers today") }
            }
            if !g.faces.isEmpty {
                HStack(spacing: -8) {
                    ForEach(g.faces.prefix(6)) { EkklesiaFaceView(name: $0.name, url: $0.avatar, size: 28, ring: true) }
                    if g.memberCount > min(6, g.faces.count) {
                        Text("+\(g.memberCount - min(6, g.faces.count))").font(.inter(11, .semibold)).foregroundStyle(.white.opacity(0.7)).padding(.leading, 14)
                    }
                }
            }
            if g.isMember {
                HStack(spacing: 10) {
                    Text(memberChip(g)).font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Nuru.gold.opacity(0.18), in: Capsule())
                        .overlay(Capsule().stroke(Nuru.gold.opacity(0.5), lineWidth: 1))
                    Spacer(minLength: 0)
                    Button {
                        if leaveArmed { leaveArmed = false; Task { await vm.after { try await MemberAPI.ekklesiaLeave() } } } else { leaveArmed = true }
                    } label: {
                        Text(leaveArmed ? "Tap again to leave" : "Leave").font(.inter(11, .medium)).foregroundStyle(.white.opacity(leaveArmed ? 0.9 : 0.45)).padding(6)
                    }.buttonStyle(.plain)
                }
                if g.needsMeToday > 0 {
                    Text(EkklesiaWords.memberLine(needsMeToday: g.needsMeToday, urgent: g.urgentCount)).font(.inter(12, .medium)).foregroundStyle(Nuru.gold)
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        Haptics.tap()
                        Task { await vm.after { try await MemberAPI.ekklesiaJoin() } }
                    } label: {
                        Text("Stand in the gap").font(.inter(13, .bold)).foregroundStyle(Nuru.navyDeep)
                            .padding(.horizontal, 18).padding(.vertical, 10).background(Nuru.gold, in: Capsule())
                    }.buttonStyle(.plain)
                    Text("Join as an intercessor").font(.inter(11, .regular)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func memberChip(_ g: EkklesiaGroup) -> String {
        var s = g.myRole == "leader" ? "You lead the watch" : "You stand on the watch"
        if g.myDays > 0 { s += " · \(g.myDays) \(g.myDays == 1 ? "day" : "days")" }
        return s
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text("\(n)").font(.fraunces(18, .semibold)).foregroundStyle(Nuru.gold)
            Text(label).font(.inter(11, .regular)).foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: bringing a need

    private var bringPrompt: some View {
        Button { composing = true } label: {
            HStack(spacing: 12) {
                ZStack { Circle().fill(Color.white).frame(width: 36, height: 36); Icon(.plus, size: 18, color: Nuru.navy) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bring a need").font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                    Text("Every intercessor hears it at once.").font(.inter(11, .regular)).foregroundStyle(Nuru.ink600)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 14, color: Nuru.ink400)
            }
            .padding(12)
            .background(Nuru.goldTint.opacity(0.55), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
        }.buttonStyle(.pressableSubtle)
    }

    private func statusPill(_ label: String, _ count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(.inter(12, .bold)).foregroundStyle(on ? .white : Nuru.ink600)
                if count > 0 {
                    Text("\(count)").font(.inter(11, .bold)).foregroundStyle(on ? Nuru.navyDeep : Nuru.goldChipText)
                        .padding(.horizontal, 7).padding(.vertical, 1).background(on ? Nuru.gold : Nuru.goldChipBg, in: Capsule())
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(on ? Nuru.navy : Color.white, in: Capsule())
            .overlay(Capsule().stroke(on ? .clear : Nuru.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func previewCard(_ p: EkklesiaPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            EkklesiaChips(urgent: p.urgency == "urgent", pinned: false)
            Text(p.title).font(.fraunces(16, .semibold)).foregroundStyle(Nuru.ink)
            HStack(spacing: 6) {
                Icon(.lock, size: 14, color: Nuru.ink400)
                Text((EkklesiaWords.countsLine(intercessors: p.intercessorCount, prayers: 0, updates: 0).map { "\($0) · " } ?? "") + timeAgo(p.createdAt))
                    .font(.inter(11, .regular)).foregroundStyle(Nuru.ink400)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}

/// URGENT / PINNED, as on Android.
struct EkklesiaChips: View {
    let urgent: Bool
    let pinned: Bool
    var body: some View {
        HStack(spacing: 6) {
            if pinned {
                Text("PINNED").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.goldChipText)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Nuru.goldChipBg, in: Capsule())
            }
            if urgent {
                Text("URGENT").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.warning)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Nuru.warning.opacity(0.12), in: Capsule())
            }
        }
    }
}

/// "I interceded" — gold until today's prayer is counted, then a quiet check.
struct EkklesiaIntercedeButton: View {
    let r: EkklesiaRequest
    let onIntercede: () -> Void
    var body: some View {
        let done = r.iPrayedToday
        Button {
            guard !done else { return }
            Haptics.tap()
            onIntercede()
        } label: {
            HStack(spacing: 6) {
                Icon(done ? .check : .flame, size: 14, color: done ? Nuru.goldChipText : Nuru.navyDeep)
                Text(done ? (r.myPrayerDays > 1 ? "Prayed today · \(r.myPrayerDays) days" : "Prayed today") : "I interceded")
                    .font(.inter(12, .bold)).foregroundStyle(done ? Nuru.goldChipText : Nuru.navyDeep)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(done ? Color.white : Nuru.gold, in: Capsule())
            .overlay(Capsule().stroke(done ? Nuru.gold : .clear, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct EkklesiaRequestCard: View {
    let r: EkklesiaRequest
    let onIntercede: () -> Void
    init(_ r: EkklesiaRequest, onIntercede: @escaping () -> Void) { self.r = r; self.onIntercede = onIntercede }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                EkklesiaFaceView(name: r.authorName, url: r.authorAvatar, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.authorName).font(.inter(12, .bold)).foregroundStyle(Nuru.ink).nuruLineLimit(1)
                    Text(timeAgo(r.createdAt)).font(.inter(11, .regular)).foregroundStyle(Nuru.ink400)
                }
                Spacer(minLength: 0)
                if r.isAnswered {
                    HStack(spacing: 4) { Icon(.check, size: 14, color: Nuru.successText); Text("Answered").font(.inter(11, .medium)).foregroundStyle(Nuru.successText) }
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Nuru.successBg, in: Capsule())
                } else {
                    EkklesiaChips(urgent: r.isUrgent, pinned: r.isPinned)
                }
            }
            Text(r.title).font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink).padding(.top, 10).multilineTextAlignment(.leading)
            if let w = r.forWhom, !w.isEmpty {
                Text("For \(w)").font(.inter(12, .medium)).foregroundStyle(Nuru.goldChipText).padding(.top, 2)
            }
            Text(r.body).font(.inter(13, .regular)).foregroundStyle(Nuru.ink600).lineSpacing(3).nuruLineLimit(3).padding(.top, 6).multilineTextAlignment(.leading)
            if let n = r.answeredNote, !n.isEmpty {
                Text("“\(n)”").font(.inter(12, .regular)).foregroundStyle(Nuru.successText).padding(.top, 6)
            }
            HStack(spacing: 10) {
                if !r.isAnswered { EkklesiaIntercedeButton(r: r, onIntercede: onIntercede) }
                if let c = EkklesiaWords.countsLine(intercessors: r.intercessorCount, prayers: r.prayerCount, updates: r.updateCount) {
                    Text(c).font(.inter(11, .regular)).foregroundStyle(Nuru.ink400).nuruLineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(r.isUrgent && !r.isAnswered ? Nuru.warning.opacity(0.35) : Nuru.border, lineWidth: 1))
    }
}

/// Bringing a need to the watch.
struct EkklesiaBringSheet: View {
    let onBrought: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var forWhom = ""
    @State private var body_ = ""
    @State private var urgent = false
    @State private var posting = false
    @State private var error: String?
    // Stable ids across retries: a second tap cannot bring the need twice.
    @State private var ids = (UUID().uuidString, UUID().uuidString)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bring a need to the watch").font(.fraunces(18, .semibold)).foregroundStyle(Nuru.navy)
            Text("Say who it is for and what to pray. Every intercessor is told once; they carry it until it is answered.")
                .font(.inter(12, .regular)).foregroundStyle(Nuru.ink600)
            field($title, "What to pray for (a short title)")
            field($forWhom, "For whom (optional)")
            field($body_, "The need, as you would tell the watch…", lines: 4)
            HStack(spacing: 8) {
                Button { urgent.toggle() } label: {
                    HStack(spacing: 6) {
                        Icon(.flag, size: 14, color: urgent ? Nuru.warning : Nuru.ink400)
                        Text(urgent ? "Urgent" : "Mark urgent").font(.inter(12, .semibold)).foregroundStyle(urgent ? Nuru.warning : Nuru.ink600)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(urgent ? Nuru.warning.opacity(0.12) : Nuru.coolPaper, in: Capsule())
                    .overlay(Capsule().stroke(urgent ? Nuru.warning : Nuru.border, lineWidth: 1))
                }.buttonStyle(.plain)
                Text("Urgent needs rise to the top and say so in the push.").font(.inter(11, .regular)).foregroundStyle(Nuru.ink400)
            }
            if let error { Text(error).font(.inter(12, .medium)).foregroundStyle(Nuru.danger) }
            Button {
                posting = true; error = nil
                Task {
                    do {
                        try await MemberAPI.ekklesiaBring(requestId: ids.0, clientMutationId: ids.1,
                                                          title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                          body: body_.trimmingCharacters(in: .whitespacesAndNewlines),
                                                          forWhom: forWhom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : forWhom.trimmingCharacters(in: .whitespacesAndNewlines),
                                                          urgent: urgent)
                        posting = false
                        onBrought(); dismiss()
                    } catch {
                        posting = false
                        self.error = error.localizedDescription
                    }
                }
            } label: {
                Text(posting ? "Bringing…" : "Bring it to the watch").font(.inter(14, .bold)).foregroundStyle(Nuru.navyDeep)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).background(canSend ? Nuru.gold : Nuru.gold.opacity(0.4), in: Capsule())
            }
            .buttonStyle(.plain).disabled(!canSend)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Nuru.paper)
        .presentationDetents([.large])
    }

    private var canSend: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !body_.trimmingCharacters(in: .whitespaces).isEmpty && !posting }

    private func field(_ text: Binding<String>, _ hint: String, lines: Int = 1) -> some View {
        TextField(hint, text: text, axis: .vertical)
            .frame(minHeight: CGFloat(lines) * 22, alignment: .top)
            .font(.inter(14, .regular)).foregroundStyle(Nuru.ink)
            .padding(12)
            .background(Nuru.coolPaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}
