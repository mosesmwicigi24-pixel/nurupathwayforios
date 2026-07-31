// Nuru Live L5/L6 — the broadcaster's raised-hands + guests sheet, opened
// from GoLiveBroadcastView's ✋ control. Reads live off `BroadcastController`
// (whose pulse poll keeps running underneath at its normal 3s cadence while
// this sheet is open) so the hand queue updates in place rather than going
// stale the moment it's presented.
//
// "Lower" on a hand is LOCAL-ONLY: the pinned wire contract's
// `POST /hand {raised}` always targets the CALLING user — there's no
// broadcaster-authority parameter to force someone else's hand down. Tapping
// it just clears that row from THIS sheet's view for the rest of the stream;
// it never claims the member's own hand state (or the server's) changed.
import SwiftUI

struct LiveHandsGuestsSheet: View {
    @ObservedObject var controller: BroadcastController
    @Environment(\.dismiss) private var dismiss

    @State private var dismissedHandIds: Set<String> = []
    @State private var actioningUserId: String?

    private static let maxGuests = 6

    private var hands: [LiveHandRow] {
        (controller.pulse?.hands ?? []).filter { !dismissedHandIds.contains($0.userId) }
    }
    private var guests: [LiveGuestRow] {
        (controller.pulse?.guests ?? []).filter(\.isActive)
    }
    private var activeGuestCount: Int { guests.count }
    private var atGuestCap: Bool { activeGuestCount >= Self.maxGuests }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Nuru.S.lg) {
                    handsSection
                    if !guests.isEmpty { guestsSection }
                }
                .padding(Nuru.S.base)
                .padding(.bottom, Nuru.S.xl)
            }
            .background(Nuru.paper.ignoresSafeArea())
            .navigationTitle("Raised hands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Icon(.x, size: 15, color: Nuru.ink600)
                            .frame(width: 30, height: 30)
                            .background(Nuru.white, in: Circle())
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Hands

    private var handsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RAISED HANDS · \(hands.count)")
                .font(.nCardKicker).kerning(1.2).foregroundStyle(Nuru.goldLo)
            if hands.isEmpty {
                Text("No hands raised right now.")
                    .font(.inter(12)).foregroundStyle(Nuru.muted)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(hands) { hand in
                        handRow(hand)
                        if hand.id != hands.last?.id {
                            Divider().overlay(Nuru.border)
                        }
                    }
                }
                .padding(.horizontal, Nuru.S.base).padding(.vertical, 4)
                .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            }
        }
    }

    private func handRow(_ hand: LiveHandRow) -> some View {
        HStack(spacing: 12) {
            Avatar(url: hand.avatarUrl, name: hand.fullName, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(hand.fullName).font(.nRowTitle).foregroundStyle(Nuru.ink)
                Text("raised \(timeAgo(hand.raisedAt)) ago").font(.nCardMeta).foregroundStyle(Nuru.muted)
            }
            Spacer(minLength: 8)
            if let status = guestStatus(for: hand.userId) {
                Text(status == "accepted" ? "Joining soon" : "Invited")
                    .font(.inter(10, .semibold)).foregroundStyle(Nuru.ink400)
            } else {
                Button {
                    Haptics.tap()
                    Task { await invite(hand.userId) }
                } label: {
                    Text(atGuestCap ? "6 guests max" : "Invite to join")
                        .font(.inter(11, .bold))
                        .foregroundStyle(atGuestCap ? Nuru.ink400 : Nuru.navy)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(atGuestCap ? Nuru.mutedBg : Nuru.gold, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(atGuestCap || actioningUserId == hand.userId)
            }
            Button {
                Haptics.tap()
                dismissedHandIds.insert(hand.userId)
            } label: {
                Text("Lower").font(.inter(11, .semibold)).foregroundStyle(Nuru.ink400)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Nuru.mutedBg, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(.vertical, 8)
    }

    private func guestStatus(for userId: String) -> String? {
        controller.pulse?.guests.first { $0.userId == userId && $0.isActive }?.status
    }

    // MARK: Guests — "video is L6"; accepted rows read "joining soon" honestly.

    private var guestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GUESTS · \(activeGuestCount)/\(Self.maxGuests)")
                .font(.nCardKicker).kerning(1.2).foregroundStyle(Nuru.goldLo)
            VStack(spacing: 0) {
                ForEach(guests) { guest in
                    guestRow(guest)
                    if guest.id != guests.last?.id {
                        Divider().overlay(Nuru.border)
                    }
                }
            }
            .padding(.horizontal, Nuru.S.base).padding(.vertical, 4)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        }
    }

    private func guestRow(_ guest: LiveGuestRow) -> some View {
        HStack(spacing: 12) {
            Avatar(url: guest.avatarUrl, name: guest.fullName, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(guest.fullName).font(.nRowTitle).foregroundStyle(Nuru.ink)
                Text(guest.status == "accepted" ? "Joining soon — video in the next update" : "Invited — waiting to accept")
                    .font(.nCardMeta).foregroundStyle(guest.status == "accepted" ? Nuru.success : Nuru.muted)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                Task { await remove(guest.userId) }
            } label: {
                Text("Remove").font(.inter(11, .semibold)).foregroundStyle(Nuru.danger)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Nuru.danger.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(actioningUserId == guest.userId)
        }
        .padding(.vertical, 8)
    }

    // MARK: Actions

    private func invite(_ userId: String) async {
        guard actioningUserId == nil else { return }
        actioningUserId = userId
        defer { actioningUserId = nil }
        try? await MemberAPI.inviteLiveGuest(streamId: controller.session.stream.streamId, userId: userId)
        await controller.pollPulseNow()
    }

    private func remove(_ userId: String) async {
        guard actioningUserId == nil else { return }
        actioningUserId = userId
        defer { actioningUserId = nil }
        try? await MemberAPI.removeLiveGuest(streamId: controller.session.stream.streamId, userId: userId)
        await controller.pollPulseNow()
    }
}
