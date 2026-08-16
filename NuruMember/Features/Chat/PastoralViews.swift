// Chat Redesign C3b — the shared "one private thread" hero card used by the
// My Discipler and Talk with My Pastor tabs, and the pastor/SuperAdmin-facing
// "Talk with Your Pastor" inbox.
//
// The inbox sits behind the SAME server password step-up as the Broadcast
// (GET /chat/pastoral/inbox answers 403 password_required without a fresh
// confirmation), so it reuses the exact Broadcast machinery: BroadcastLock's
// Face-ID-released password fast path, PasswordConfirmSheet as the typed
// fallback, and the shared 15-minute window — one door state for both rooms.
import SwiftUI

// MARK: - Hero card for a single private thread

struct PrivateThreadCard: View {
    let kicker: String
    let title: String
    let subtitle: String
    let detail: String?
    let avatarUrl: String?
    let privacyLine: String
    let unread: Int
    let busy: Bool
    let cta: String
    /// Talk with My Pastor only: the device-local gate is on and sealed — the
    /// button says so, and the tap raises the OS prompt before anything else.
    let locked: Bool
    /// Server-side per-member mute (Chat Redesign C4) — the small bell-slash
    /// glyph beside the kicker, same signal as the ⋮ menu's Mute/Unmute label.
    var muted: Bool = false
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Icon(.heartHandshake, size: 12, color: Color(hex: 0xB08A1E))
                Text(kicker).font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0xB08A1E))
                if muted {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: 0x9AA3AF))
                }
                Spacer(minLength: 0)
                if unread > 0 {
                    Text("\(unread) new").font(.inter(10, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Nuru.goldGradient, in: Capsule())
                }
            }
            HStack(spacing: 14) {
                Avatar(url: avatarUrl, name: title, size: 56)
                    .padding(2.5)
                    .background(Nuru.goldGradient, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.fraunces(18, .semibold)).kerning(-0.3).foregroundStyle(Nuru.navy).lineLimit(1)
                    Text(subtitle).font(.inter(12)).foregroundStyle(Color(hex: 0x59667C)).lineLimit(2)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.nCardMeta).foregroundStyle(Color(hex: 0x9AA3AF)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            // The honest privacy line, said before the first tap — the same
            // words the thread itself repeats above the composer.
            HStack(spacing: 6) {
                Icon(.lock, size: 11, color: Nuru.goldChipText)
                Text(privacyLine).font(.inter(11, .medium)).foregroundStyle(Nuru.goldChipText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button(action: onOpen) {
                Group {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 7) {
                            if locked {
                                Image(systemName: "faceid").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            } else {
                                Icon(.messageCircle, size: 14, color: .white)
                            }
                            Text(locked ? "Unlock & open" : cta).font(.nCardCTA).foregroundStyle(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Nuru.goldGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Nuru.gold.opacity(0.5), radius: 9, y: 5)
            }
            .buttonStyle(.pressable)
            .disabled(busy)
        }
        .padding(Nuru.S.base)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }
}

// MARK: - Pastor-facing inbox ("Talk with Your Pastor")

/// The pastor's list of pastoral threads — server-gated (§5.3) and opened with
/// the SAME lock state as the Broadcast: if the SuperAdmin already unlocked one
/// sealed room this session, the other is open too (they share the server's
/// 15-minute step-up window, so pretending otherwise would be theater).
struct PastoralInboxSection: View {
    let onOpen: (PastoralInboxRow) -> Void

    @ObservedObject private var lock = BroadcastLock.shared
    @State private var asking = false
    @State private var tryingFace = false
    @State private var rows: [PastoralInboxRow]?
    @State private var loadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Icon(.heartHandshake, size: 12, color: Color(hex: 0xB08A1E))
                Text("TALK WITH YOUR PASTOR — INBOX").font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0xB08A1E))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            if lock.isOpen {
                openBody
            } else {
                gate
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: lock.isOpen)
        .sheet(isPresented: $asking) {
            PasswordConfirmSheet(reason: "Pastoral conversations are private between each member and their pastor. Confirm it's you to open the inbox.") {
                // markOpen happened inside the sheet; the section re-renders open.
            }
        }
        .task {
            if lock.isOpen { await load() }
            else { await tryFaceFirst() }
        }
        .onChange(of: lock.isOpen) { _, open in
            if open, rows == nil { Task { await load() } }
        }
    }

    @ViewBuilder private var openBody: some View {
        if let rows {
            if rows.isEmpty {
                Text("No pastoral conversations yet — members will appear here the moment they open one.")
                    .font(.nCardBody).foregroundStyle(Color(hex: 0x74808F))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22).padding(.horizontal, Nuru.S.base)
                    .multilineTextAlignment(.center)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        Button {
                            Haptics.tap()
                            onOpen(row)
                        } label: {
                            PastoralInboxRowView(row: row, divider: idx > 0)
                        }
                        .buttonStyle(.pressableSubtle)
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                .nuruShadow()
            }
        } else if loadFailed {
            Text("Couldn't load the inbox — pull to retry.")
                .font(.nCardMeta).foregroundStyle(Nuru.ink600)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
        } else {
            ProgressView().tint(Nuru.gold)
                .frame(maxWidth: .infinity).padding(.vertical, 20)
        }
    }

    /// The sealed door — compact twin of the Broadcast gate.
    private var gate: some View {
        VStack(spacing: 12) {
            Icon(.lockKeyhole, size: 24, color: Nuru.goldLight)
            Text("The inbox is sealed")
                .font(.fraunces(17, .semibold)).kerning(-0.3).foregroundStyle(.white)
            Text("What members bring to their pastor stays between them. Confirm it's you to open it for 15 minutes.")
                .font(.inter(11.5)).foregroundStyle(.white.opacity(0.72)).lineSpacing(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button {
                Haptics.action()
                Task {
                    if BroadcastLock.biometricUnlockEnrolled { await tryFaceFirst(force: true) }
                    else { asking = true }
                }
            } label: {
                Text(BroadcastLock.biometricUnlockEnrolled ? "Unlock with \(BroadcastLock.biometryName)" : "Enter password")
                    .font(.nCardCTA).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Nuru.goldGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private func tryFaceFirst(force: Bool = false) async {
        guard !lock.isOpen, !tryingFace, BroadcastLock.biometricUnlockEnrolled else { return }
        if !force, asking { return }
        tryingFace = true
        defer { tryingFace = false }
        if await lock.unlockWithBiometrics() {
            Haptics.success()
        } else if force {
            asking = true
        }
    }

    private func load() async {
        do {
            rows = try await MemberAPI.pastoralInbox()
            loadFailed = false
        } catch let e as APIError where e.needsPasswordConfirm {
            // The 15 minutes lapsed — seal the door again; the gate takes over.
            BroadcastLock.shared.relock()
        } catch {
            if rows == nil { loadFailed = true }
        }
    }
}

private struct PastoralInboxRowView: View {
    let row: PastoralInboxRow
    let divider: Bool

    var body: some View {
        HStack(spacing: 14) {
            Avatar(url: row.memberAvatarUrl, name: row.memberName, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.memberName)
                    .font(.inter(12, .semibold)).kerning(-0.12).foregroundStyle(Nuru.navy).lineLimit(1)
                Text(row.lastBody ?? "No messages yet")
                    .font(.inter(10)).foregroundStyle(Color(hex: 0x6A7686)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Icon(.chevronRight, size: 14, color: Color(hex: 0xCBD5E1))
        }
        .padding(.horizontal, Nuru.S.base)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { if divider { Rectangle().fill(Nuru.border).frame(height: 1) } }
    }
}
