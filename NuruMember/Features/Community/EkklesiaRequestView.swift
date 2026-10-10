// One need on the watch: the request in full, the act of interceding, who is
// standing on it, the words written back (updates and testimony), and the
// requester's or a leader's hand on it (answered, pinned, withdrawn).
import SwiftUI

@MainActor
final class EkklesiaRequestViewModel: ObservableObject {
    @Published var detail: EkklesiaRequestDetail?
    @Published var loading = true
    @Published var failure: Error?
    let requestId: String
    init(requestId: String) { self.requestId = requestId }
    func load() async {
        loading = true; failure = nil
        do { detail = try await MemberAPI.ekklesiaRequest(requestId) } catch { failure = error }
        loading = false
    }
    func after(_ work: () async throws -> Void) async {
        do { try await work() } catch { failure = error }
        EkklesiaPulse.shared.invalidate()
        await load()
        await EkklesiaPulse.shared.refresh(force: true)
    }
}

struct EkklesiaRequestView: View {
    @StateObject private var vm: EkklesiaRequestViewModel
    @ObservedObject private var pulse = EkklesiaPulse.shared
    @Environment(\.dismiss) private var dismiss
    @State private var closing = false
    @State private var withdrawArmed = false
    @State private var text = ""
    @State private var testimony = false
    @State private var sending = false
    @State private var ids = (UUID().uuidString, UUID().uuidString)

    init(requestId: String) { _vm = StateObject(wrappedValue: EkklesiaRequestViewModel(requestId: requestId)) }

    private var isLeader: Bool { pulse.summary?.isLeader == true }
    private var isMember: Bool { pulse.summary?.isMember == true }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: Nuru.navy).frame(width: 40, height: 40)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }.buttonStyle(.plain)
                Text("EKKLESIA · THE WATCH").font(.inter(11, .semibold)).kerning(1.8).foregroundStyle(Nuru.goldChipText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Nuru.S.screen).padding(.vertical, 12)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if let d = vm.detail {
                        let r = d.request
                        requestFull(r)
                        if !r.isAnswered {
                            HStack(spacing: 10) {
                                EkklesiaIntercedeButton(r: r) { Task { await vm.after { try await MemberAPI.ekklesiaIntercede(r.requestId) } } }
                                if let c = EkklesiaWords.countsLine(intercessors: r.intercessorCount, prayers: r.prayerCount, updates: 0) {
                                    Text(c).font(.inter(11, .regular)).foregroundStyle(Nuru.ink400)
                                }
                            }
                        }
                        if !d.intercessors.isEmpty { standing(d) }
                        if !d.updates.isEmpty { updates(d.updates) }
                        if isMember || r.mine { writeBack(r.requestId) }
                        if r.mine || isLeader { actions(r) }
                    } else if vm.loading {
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white).frame(height: 180)
                    } else if let f = vm.failure {
                        NuruStateView(state: .failed(.failure(f)), retry: { Task { await vm.load() } }, back: { dismiss() })
                    }
                }
                .padding(.horizontal, Nuru.S.screen).padding(.bottom, 32)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await pulse.refresh(); await vm.load() }
        .sheet(isPresented: $closing) {
            EkklesiaAnsweredSheet(requestId: vm.requestId) { Task { await vm.after {} } }
        }
    }

    private func requestFull(_ r: EkklesiaRequest) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                EkklesiaFaceView(name: r.authorName, url: r.authorAvatar, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.authorName).font(.inter(12, .bold)).foregroundStyle(Nuru.ink)
                    Text("brought this \(timeAgo(r.createdAt))").font(.inter(11, .regular)).foregroundStyle(Nuru.ink400)
                }
                Spacer(minLength: 0)
                if r.isAnswered {
                    Text("Answered").font(.inter(11, .medium)).foregroundStyle(Nuru.successText).padding(.horizontal, 10).padding(.vertical, 4).background(Nuru.successBg, in: Capsule())
                } else {
                    EkklesiaChips(urgent: r.isUrgent, pinned: r.isPinned)
                }
            }
            Text(r.title).font(.fraunces(22, .semibold)).foregroundStyle(Nuru.navy).padding(.top, 12)
            if let w = r.forWhom, !w.isEmpty { Text("For \(w)").font(.inter(13, .medium)).foregroundStyle(Nuru.goldChipText).padding(.top, 2) }
            Text(r.body).font(.inter(14, .regular)).foregroundStyle(Nuru.ink).lineSpacing(5).padding(.top, 10)
            if r.isAnswered {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ANSWERED" + (r.answeredAt.map { " · \(timeAgo($0))" } ?? "")).font(.inter(11, .bold)).kerning(1.4).foregroundStyle(Nuru.successText)
                    if let n = r.answeredNote, !n.isEmpty { Text("“\(n)”").font(.inter(13, .regular)).foregroundStyle(Nuru.successText).lineSpacing(4) }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Nuru.successBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).padding(.top, 12)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func standing(_ d: EkklesiaRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STANDING ON THIS NEED").font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Nuru.eyebrow)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(d.intercessors.prefix(12)) { i in
                    HStack(spacing: 10) {
                        EkklesiaFaceView(name: i.name, url: i.avatar, size: 28)
                        Text(i.me ? "You" : i.name).font(.inter(13, .medium)).foregroundStyle(Nuru.ink)
                        Spacer(minLength: 0)
                        Text(i.days == 1 ? "1 day" : "\(i.days) days").font(.inter(11, .regular)).foregroundStyle(Nuru.ink400)
                    }
                }
                if d.request.intercessorCount > d.intercessors.count {
                    Text("and \(d.request.intercessorCount - d.intercessors.count) more").font(.inter(11, .regular)).foregroundStyle(Nuru.ink400)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
    }

    private func updates(_ list: [EkklesiaUpdate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORD BACK TO THE WATCH").font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Nuru.eyebrow)
            ForEach(list) { u in
                let t = u.kind == "testimony"
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        EkklesiaFaceView(name: u.authorName, url: u.authorAvatar, size: 26)
                        Text(u.mine ? "You" : u.authorName).font(.inter(12, .bold)).foregroundStyle(Nuru.ink)
                        Spacer(minLength: 0)
                        if t { Text("TESTIMONY").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.goldChipText) }
                        Text(timeAgo(u.createdAt)).font(.inter(11, .regular)).foregroundStyle(Nuru.ink400)
                    }
                    Text(u.body).font(.inter(13, .regular)).foregroundStyle(Nuru.ink).lineSpacing(4)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(t ? Nuru.goldTint.opacity(0.5) : Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(t ? Nuru.gold.opacity(0.35) : Nuru.border, lineWidth: 1))
            }
        }
    }

    private func writeBack(_ requestId: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Write back to the watch").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
            TextField(testimony ? "What God did…" : "How it is going, what to pray now…", text: $text, axis: .vertical)
                .frame(minHeight: 48, alignment: .top)
                .font(.inter(14, .regular)).foregroundStyle(Nuru.ink).padding(12)
                .background(Nuru.coolPaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            HStack(spacing: 8) {
                kindPill("Update", on: !testimony) { testimony = false }
                kindPill("Testimony", on: testimony) { testimony = true }
                Spacer(minLength: 0)
                Button {
                    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !body.isEmpty, !sending else { return }
                    sending = true
                    Task {
                        await vm.after { try await MemberAPI.ekklesiaWriteBack(requestId, updateId: ids.0, clientMutationId: ids.1, body: body, testimony: testimony) }
                        sending = false
                        if vm.failure == nil { text = ""; ids = (UUID().uuidString, UUID().uuidString) }
                    }
                } label: {
                    HStack(spacing: 6) { Icon(.send, size: 14, color: Nuru.navyDeep); Text(sending ? "Sending…" : "Send").font(.inter(12, .bold)).foregroundStyle(Nuru.navyDeep) }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(text.trimmingCharacters(in: .whitespaces).isEmpty || sending ? Nuru.border : Nuru.gold, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func kindPill(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.inter(11, .bold)).foregroundStyle(on ? .white : Nuru.ink600)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(on ? Nuru.navy : Color.white, in: Capsule())
                .overlay(Capsule().stroke(on ? .clear : Nuru.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func actions(_ r: EkklesiaRequest) -> some View {
        HStack(spacing: 8) {
            actionPill(r.isAnswered ? "Reopen" : "Mark answered", .check) {
                if r.isAnswered { Task { await vm.after { try await MemberAPI.ekklesiaAnswered(r.requestId, answered: false, note: nil) } } } else { closing = true }
            }
            if isLeader && !r.isAnswered {
                actionPill(r.isPinned ? "Unpin" : "Pin", .bookmark) { Task { await vm.after { try await MemberAPI.ekklesiaPinned(r.requestId, pinned: !r.isPinned) } } }
            }
            Spacer(minLength: 0)
            Button {
                if withdrawArmed {
                    Task {
                        if (try? await MemberAPI.ekklesiaWithdraw(r.requestId)) != nil { EkklesiaPulse.shared.invalidate(); dismiss() }
                    }
                } else { withdrawArmed = true }
            } label: {
                Text(withdrawArmed ? "Tap again to withdraw" : "Withdraw").font(.inter(11, .medium)).foregroundStyle(withdrawArmed ? Nuru.danger : Nuru.ink400).padding(6)
            }.buttonStyle(.plain)
        }
    }

    private func actionPill(_ label: String, _ icon: Lucide, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { Icon(icon, size: 14, color: Nuru.navy); Text(label).font(.inter(12, .semibold)).foregroundStyle(Nuru.navy) }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white, in: Capsule()).overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct EkklesiaAnsweredSheet: View {
    let requestId: String
    let onClosed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var saving = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Answered").font(.fraunces(18, .semibold)).foregroundStyle(Nuru.navy)
            Text("A word of testimony for everyone who stood on this need. The watch keeps it.").font(.inter(12, .regular)).foregroundStyle(Nuru.ink600)
            TextField("What God did (optional)", text: $note, axis: .vertical).frame(minHeight: 68, alignment: .top)
                .font(.inter(14, .regular)).foregroundStyle(Nuru.ink).padding(12)
                .background(Nuru.coolPaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            Button {
                saving = true
                Task {
                    let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    if (try? await MemberAPI.ekklesiaAnswered(requestId, answered: true, note: n.isEmpty ? nil : n)) != nil { onClosed(); dismiss() }
                    saving = false
                }
            } label: {
                Text(saving ? "Closing…" : "Mark answered").font(.inter(14, .bold)).foregroundStyle(Nuru.navyDeep)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).background(Nuru.gold, in: Capsule())
            }.buttonStyle(.plain).disabled(saving)
            Spacer(minLength: 0)
        }
        .padding(20).background(Nuru.paper).presentationDetents([.medium])
    }
}
