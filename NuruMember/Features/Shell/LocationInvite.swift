// Location-first onboarding + silent geotag refresh.
//   • LocationInviteSheet — shown ONCE right after first login: a warm ask to
//     share an approximate area so leaders can knit cells by neighborhood.
//     Accepting triggers the OS permission prompt, takes one coarse fix, and
//     POSTs /me/location. Declining never asks again (Profile keeps the switch).
//   • refreshLocationIfSharing() — every app open, if the member has said yes
//     AND the OS permission is still granted, silently re-POST a coarse fix so
//     geotagging stays current with zero further taps. Nothing runs for members
//     who declined or revoked (the server keeps only a ~1.2 km geohash either way).
import SwiftUI

enum LocationOnboarding {
    @MainActor static func refreshIfSharing() async {
        let sharing = UserDefaults.standard.bool(forKey: "nuru.privacy.shareLocation")
        guard sharing else { return }
        let lm = LocationManager()
        guard lm.isAuthorized else { return } // revoked at OS level — respect it
        if let c = await lm.requestCoarseFix() {
            try? await MemberAPI.shareLocation(lat: c.latitude, lng: c.longitude)
        }
    }
}

struct LocationInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nuru.privacy.shareLocation") private var shareLocation = false
    @StateObject private var location = LocationManager()
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 26)
            ZStack {
                Circle().fill(Color(hex: 0xE8CA6C).opacity(0.16)).frame(width: 96, height: 96)
                Text("📍").font(.system(size: 42))
            }
            Text("Be found by your church family")
                .font(.fraunces(23, .medium)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 18).padding(.horizontal, 30)
            Text("Share your approximate area — never your exact position — and your leaders can connect you with brothers and sisters near you: a cell close to home, someone to walk with.")
                .font(.inter(14.5)).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center).lineSpacing(4)
                .padding(.top, 10).padding(.horizontal, 28)
            Text("We keep only a coarse ~1 km area. You can stop sharing anytime in Profile → Settings.")
                .font(.inter(11.5)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.top, 10).padding(.horizontal, 34)
            Spacer(minLength: 20)
            VStack(spacing: 10) {
                Button {
                    Haptics.action()
                    working = true
                    Task {
                        if let c = await location.requestCoarseFix() {
                            try? await MemberAPI.shareLocation(lat: c.latitude, lng: c.longitude)
                            shareLocation = true
                        }
                        working = false
                        dismiss()
                    }
                } label: {
                    ZStack {
                        if working { ProgressView().tint(Color(hex: 0x1E2A1F)) }
                        else { Text("Share my area").font(.inter(16, .bold)).foregroundStyle(Color(hex: 0x1E2A1F)) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(LinearGradient(colors: [Color(hex: 0xE8CA6C), Color(hex: 0xB6862F)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(working)
                Button { Haptics.tap(); dismiss() } label: {
                    Text("Not now").font(.inter(14, .semibold)).foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 24).padding(.bottom, 26)
        }
        .background(
            LinearGradient(colors: [Color(hex: 0x0F2A47), Color(hex: 0x081020)],
                           startPoint: .top, endPoint: .bottom)
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
