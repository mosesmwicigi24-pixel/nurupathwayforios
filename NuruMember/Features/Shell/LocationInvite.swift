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
    @StateObject private var location = LocationManager()
    @State private var working = false
    /// Why sharing didn't take (owner decision, §7.4): the sheet stays open.
    @State private var failureLine: String?
    /// The sheet is as tall as its words — at a fixed half height its
    /// body was cut on smaller phones.
    @State private var contentHeight: CGFloat = 520

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 26)
            ZStack {
                Circle().fill(Color(hex: 0xE8CA6C).opacity(0.16)).frame(width: 96, height: 96)
                Text("📍").font(.emoji(42))
            }
            Text("Be found by your church family")
                .font(.fraunces(22, .medium)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 18).padding(.horizontal, 30)
            Text("Share your approximate area — never your exact position — and your leaders can connect you with brothers and sisters near you: a cell close to home, someone to walk with.")
                .font(.inter(14)).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center).lineSpacing(4)
                .padding(.top, 10).padding(.horizontal, 28)
            Text("We keep only a coarse ~1 km area. You can stop sharing anytime in Profile → Settings.")
                .font(.inter(12)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.top, 10).padding(.horizontal, 34)
            Spacer(minLength: 20)
            VStack(spacing: 10) {
                // The failure sits above the button (§7.4 #2), in words.
                if let failureLine {
                    Text(failureLine)
                        .font(.inter(13, .semibold)).foregroundStyle(Color(hex: 0xF4C7C3))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Haptics.action()
                    working = true
                    failureLine = nil
                    Task {
                        // Shared only once the server says so; else the
                        // member reads why and the sheet stays.
                        let outcome = await LocationSharing.set(true, using: location)
                        working = false
                        switch outcome {
                        case .saved: dismiss()
                        case .failed(let line): Haptics.error(); failureLine = line
                        }
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
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { contentHeight = g.size.height }
                .onChange(of: g.size.height) { _, h in contentHeight = h }
        })
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: [Color(hex: 0x0F2A47), Color(hex: 0x081020)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.hidden)
    }
}
