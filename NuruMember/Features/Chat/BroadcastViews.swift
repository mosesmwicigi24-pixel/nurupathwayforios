// The Broadcast, behind its lock.
//
// Tap Broadcast → Face ID rises (or the password sheet, the first time / when
// the face is not recognised) → the door opens for 15 minutes: the composer,
// the last broadcasts sent, and — inside each — the message pinned at the top
// with every answer beneath it. A response opens the private thread with that
// person, which already holds the broadcast as its first message.
//
// The lock is real, not painted on: the server refuses these reads without a
// fresh password confirmation (§5.3), and Face ID merely carries the password
// out of the Secure Enclave. Cancelling the face prompt falls back to typing.
import SwiftUI

// MARK: - The section that lives inside the Chat screen's 4th segment

struct BroadcastSection: View {
    @ObservedObject private var lock = BroadcastLock.shared
    @State private var asking = false        // the typed-password fallback sheet
    @State private var tryingFace = false    // debounce the auto Face ID attempt

    var body: some View {
        Group {
            if lock.isOpen {
                BroadcastHome()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                gate
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: lock.isOpen)
        .sheet(isPresented: $asking) {
            PasswordConfirmSheet(reason: "The Broadcast holds private conversations between you and every member. Confirm it's you to open them.") {
                // markOpen already happened inside the sheet; nothing to retry —
                // the section re-renders open on its own.
            }
        }
        .task { await tryFaceFirst() }
    }

    /// The sealed door. Face ID is attempted the moment the segment appears —
    /// the happy path is glance-and-in, no tap at all.
    private var gate: some View {
        VStack(spacing: Nuru.S.base) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Nuru.gold.opacity(0.16)).frame(width: 74, height: 74)
                    Circle().stroke(Nuru.gold.opacity(0.4), lineWidth: 1).frame(width: 74, height: 74)
                    Icon(.lockKeyhole, size: 30, color: Nuru.goldLight)
                }
                Text("The Broadcast is sealed")
                    .font(.fraunces(20, .semibold)).kerning(-0.4).foregroundStyle(.white)
                Text("What members write back is between you and them. Confirm it's you, and it opens for 15 minutes.")
                    .font(.inter(12)).foregroundStyle(.white.opacity(0.72)).lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if BroadcastLock.biometricUnlockEnrolled {
                    Button {
                        Haptics.action()
                        Task { await tryFaceFirst(force: true) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: BroadcastLock.biometryName == "Touch ID" ? "touchid" : "faceid")
                                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Nuru.navy)
                            Text("Unlock with \(BroadcastLock.biometryName)")
                                .font(.nCardCTA).foregroundStyle(Nuru.navy)
                        }
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Nuru.goldGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Nuru.gold.opacity(0.45), radius: 9, y: 5)
                    }
                    .buttonStyle(.pressable)
                }

                Button {
                    Haptics.tap()
                    asking = true
                } label: {
                    Text(BroadcastLock.biometricUnlockEnrolled ? "Use password instead" : "Enter password")
                        .font(.inter(13, .semibold))
                        .foregroundStyle(BroadcastLock.biometricUnlockEnrolled ? Color.white.opacity(0.8) : Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: BroadcastLock.biometricUnlockEnrolled ? 40 : 48)
                        .background(
                            BroadcastLock.biometricUnlockEnrolled
                                ? AnyShapeStyle(Color.clear)
                                : AnyShapeStyle(Nuru.goldGradient),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Nuru.S.lg).padding(.horizontal, Nuru.S.base)
            .background(
                LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .nuruShadow()
        }
    }

    private func tryFaceFirst(force: Bool = false) async {
        guard !lock.isOpen, !tryingFace, BroadcastLock.biometricUnlockEnrolled else { return }
        if !force, asking { return }
        tryingFace = true
        defer { tryingFace = false }
        if await lock.unlockWithBiometrics() {
            Haptics.success()
        } else if force {
            // They ASKED for the face and it didn't open — offer the keyboard,
            // don't leave them at a silent door.
            asking = true
        }
    }
}

// MARK: - Open: the composer + what has been sent

private struct BroadcastHome: View {
    @State private var list: BroadcastList?
    @State private var loadFailed = false
    @State private var showAll = false

    var body: some View {
        VStack(spacing: Nuru.S.base) {
            BroadcastComposer()

            if let list, !list.data.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("SENT TO THE CHURCH").font(.nOverline).kerning(1.6).foregroundStyle(Nuru.goldChipText)
                        Spacer(minLength: 0)
                        Text("\(list.total)").font(.nCardMeta).foregroundStyle(Nuru.ink600)
                    }
                    VStack(spacing: 8) {
                        ForEach(list.data) { b in
                            NavigationLink(value: b) { BroadcastRow(broadcast: b) }
                                .buttonStyle(.pressable)
                        }
                    }
                    if !showAll, list.total > list.data.count {
                        Button {
                            Haptics.tap()
                            showAll = true
                            Task { await load(limit: 100) }
                        } label: {
                            Text("Show all \(list.total)")
                                .font(.inter(12, .bold)).foregroundStyle(Nuru.goldChipText)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(Nuru.S.base)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                .nuruShadow()
            } else if loadFailed {
                Text("Couldn't load your broadcasts — pull to retry.")
                    .font(.nCardMeta).foregroundStyle(Nuru.ink600)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
        }
        .task { await load() }
        .refreshable { await load(limit: showAll ? 100 : 4) }
    }

    private func load(limit: Int = 4) async {
        do {
            list = try await MemberAPI.broadcasts(limit: limit)
            loadFailed = false
        } catch let e as APIError where e.needsPasswordConfirm {
            // The 15 minutes lapsed mid-screen. Seal the door again — the gate
            // takes over and Face ID re-opens it.
            BroadcastLock.shared.relock()
        } catch {
            if list == nil { loadFailed = true }
        }
    }
}

/// One sent broadcast: its words, when, and the three numbers that matter.
private struct BroadcastRow: View {
    let broadcast: Broadcast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(broadcast.body)
                .font(.fraunces(14)).foregroundStyle(Nuru.navy).lineSpacing(3)
                .lineLimit(2).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                stat(.send, "\(broadcast.recipientCount)")
                stat(.eye, "\(broadcast.seenCount)")
                stat(.messageCircle, "\(broadcast.repliedCount)")
                Spacer(minLength: 0)
                Text(relativeDay(broadcast.createdAt)).font(.nCardMeta).foregroundStyle(Nuru.ink600)
                Icon(.chevronRight, size: 13, color: Nuru.ink600.opacity(0.6))
            }
        }
        .padding(Nuru.S.md)
        .background(Nuru.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func stat(_ icon: Lucide, _ n: String) -> some View {
        HStack(spacing: 4) {
            Icon(icon, size: 11, color: Nuru.goldChipText)
            Text(n).font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600)
        }
    }
}

// MARK: - Detail: the message pinned, the church answering beneath it

struct BroadcastDetailView: View {
    let broadcast: Broadcast

    @State private var detail: BroadcastDetail?
    @State private var loadFailed = false
    @State private var showRecipients = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                pinned
                if let d = detail {
                    ticksSummary(d)
                    if showRecipients { recipientsList(d) }
                    responsesWall(d)
                } else if loadFailed {
                    Text("Couldn't load the responses — pull to retry.")
                        .font(.nCardMeta).foregroundStyle(Nuru.ink600)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    HStack { Spacer(); ProgressView().tint(Nuru.gold); Spacer() }.padding(.vertical, 40)
                }
            }
            .padding(Nuru.S.screen)
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationTitle("Broadcast")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    /// The word itself, pinned — navy, serif, unmistakably THE message.
    private var pinned: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Icon(.megaphone, size: 12, color: Nuru.goldLight)
                Text("TO EVERY MEMBER").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldLight)
                Spacer(minLength: 0)
                Text(relativeDay((detail?.createdAt) ?? broadcast.createdAt))
                    .font(.nCardMeta).foregroundStyle(.white.opacity(0.6))
            }
            Text((detail?.body).flatMap { $0.isEmpty ? nil : $0 } ?? broadcast.body)
                .font(.fraunces(17)).foregroundStyle(.white).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(
            LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .nuruShadow()
    }

    /// Delivered · seen · answered — one honest line, expandable to names.
    private func ticksSummary(_ d: BroadcastDetail) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showRecipients.toggle() }
        } label: {
            HStack(spacing: 14) {
                tick(one: true, "\(d.deliveredCount) delivered")
                tick(one: false, "\(d.seenCount) seen")
                Spacer(minLength: 0)
                Icon(showRecipients ? .chevronDown : .chevronRight, size: 14, color: Nuru.ink600)
            }
            .padding(.horizontal, Nuru.S.md).padding(.vertical, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// WhatsApp's grammar, kept honest: one blue tick = it is in their thread
    /// (a server-side fact), two = they opened it.
    private func tick(one: Bool, _ label: String) -> some View {
        HStack(spacing: 5) {
            HStack(spacing: -4) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                if !one { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            }
            .foregroundStyle(Color(hex: 0x3DA8E0))
            Text(label).font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600)
        }
    }

    private func recipientsList(_ d: BroadcastDetail) -> some View {
        VStack(spacing: 0) {
            ForEach(d.recipients) { r in
                HStack(spacing: 10) {
                    Avatar(url: r.avatarUrl, name: r.fullName, size: 30)
                    Text(r.fullName).font(.inter(13, .medium)).foregroundStyle(Nuru.navy)
                    Spacer(minLength: 0)
                    HStack(spacing: -4) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        if r.seen { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                    }
                    .foregroundStyle(r.seen ? Color(hex: 0x3DA8E0) : Nuru.ink600.opacity(0.45))
                }
                .padding(.horizontal, Nuru.S.md).padding(.vertical, 8)
                if r.id != d.recipients.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func responsesWall(_ d: BroadcastDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(d.responses.isEmpty ? "NO ANSWERS YET" : "THE CHURCH ANSWERS")
                .font(.nOverline).kerning(1.6).foregroundStyle(Nuru.goldChipText)
            if d.responses.isEmpty {
                VStack(spacing: 8) {
                    Icon(.messageCircle, size: 22, color: Nuru.gold)
                    Text("When someone writes back, their words gather here — and only you see them.")
                        .font(.inter(12)).foregroundStyle(Nuru.ink600).lineSpacing(3)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            } else {
                ForEach(d.responses) { r in
                    NavigationLink(value: threadStub(for: r)) { ResponseRow(response: r) }
                        .buttonStyle(.pressable)
                }
            }
        }
    }

    /// A response's thread, as a pushable conversation. The stub hydrates in
    /// ChatThreadView — the sanctioned pattern from ChatView's person deep-link.
    private func threadStub(for r: BroadcastResponse) -> ChatConversation {
        ChatConversation(conversationId: r.conversationId, kind: "dm", isPublic: false,
                         title: r.fullName, topic: nil, category: nil, memberCount: 2,
                         lastBody: nil, lastType: nil, lastAt: nil, lastAuthor: nil,
                         unread: 0, avatarUrl: r.avatarUrl, peerUserId: r.userId)
    }

    private func load() async {
        do {
            detail = try await MemberAPI.broadcastDetail(broadcast.broadcastId)
            loadFailed = false
        } catch let e as APIError where e.needsPasswordConfirm {
            BroadcastLock.shared.relock()
        } catch {
            if detail == nil { loadFailed = true }
        }
    }
}

/// One person answering: who, when, what they said — and the door to the
/// private thread it lives in.
private struct ResponseRow: View {
    let response: BroadcastResponse

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(url: response.avatarUrl, name: response.fullName, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(response.fullName).font(.inter(13, .bold)).foregroundStyle(Nuru.navy)
                    Spacer(minLength: 8)
                    Text(relativeDay(response.createdAt)).font(.nCardMeta).foregroundStyle(Nuru.ink600)
                }
                Text(response.body.isEmpty ? "📎 Attachment" : response.body)
                    .font(.inter(13)).foregroundStyle(Nuru.ink600).lineSpacing(3)
                    .lineLimit(3).multilineTextAlignment(.leading)
                if response.fromThem > 1 {
                    Text("\(response.fromThem) messages in your conversation")
                        .font(.inter(10, .semibold)).foregroundStyle(Nuru.goldChipText)
                }
            }
            Icon(.chevronRight, size: 14, color: Nuru.ink600.opacity(0.5))
                .padding(.top, 10)
        }
        .padding(Nuru.S.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}

// MARK: - Small shared bits

/// "Just now" / "2h" / "Tue" / "5 Jul" — the inbox's own vocabulary.
private func relativeDay(_ iso: String?) -> String {
    guard let iso,
          let d = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    else { return "" }
    let s = Date().timeIntervalSince(d)
    if s < 90 { return "Just now" }
    if s < 3600 { return "\(Int(s / 60))m" }
    if s < 86_400 { return "\(Int(s / 3600))h" }
    let f = DateFormatter()
    f.dateFormat = s < 6 * 86_400 ? "EEE" : "d MMM"
    return f.string(from: d)
}
