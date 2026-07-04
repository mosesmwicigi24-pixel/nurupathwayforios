// VideoPlayerPage — the ONE way every video opens across the app (mirrors how
// the Plans day video presents): a full-bleed dark page shown via
// `fullScreenCover`, with the poster behind a scrim, a lower-third overlay
// (gold kicker · serif title · short summary · optional quick-notes line) and
// a white "Start watching" capsule. Tapping play swaps the poster for the
// shared WKWebView player (InlineVideoPlayer — YouTube/Vimeo embeds or an
// inline HTML5 <video> for direct/cloudinary URLs). A circular ✕ in the
// top-left dismisses at any point.
//
//   .fullScreenCover(isPresented: $show) {
//       VideoPlayerPage(urlString: url, title: "…", summary: "…")
//   }
import SwiftUI

struct VideoPlayerPage: View {
    let urlString: String
    /// Provider tag when the payload carries one; nil → sniffed from the URL.
    var source: String? = nil
    var externalVideoId: String? = nil
    var kicker: String = "WATCH"
    let title: String
    var summary: String? = nil
    /// Optional one-liner under the summary (e.g. "Sent Jun 12" / "Have your
    /// journal ready"), rendered with a small pen glyph.
    var quickNote: String? = nil
    var posterUrl: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var playing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if playing {
                InlineVideoPlayer(urlString: urlString, source: source, externalVideoId: externalVideoId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else {
                poster
                LinearGradient(
                    colors: [Color.black.opacity(0.15), Color.black.opacity(0.55), Color.black.opacity(0.88)],
                    startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                lowerThird
            }

            closeButton
        }
        // Poster → player is a crossfade, not a hard cut.
        .animation(.easeInOut(duration: 0.3), value: playing)
        .preferredColorScheme(.dark)
    }

    // MARK: full-bleed poster (branded gradient when there's no artwork)

    @ViewBuilder
    private var poster: some View {
        // Color.clear owns the layout size; the fill image lives in an overlay
        // so its oversized "fill" size can never inflate the page ZStack (the
        // radio-screen edge-spill bug family — a flexible max-infinity frame
        // still adopts an oversized child's size as its lower bound).
        Color.clear
            .overlay {
                if let u = posterUrl.flatMap(URL.init) {
                    CachedAsyncImage(url: u) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                        else { Nuru.navyGradient }
                    }
                } else {
                    Nuru.navyGradient
                }
            }
            .clipped()
            .ignoresSafeArea()
    }

    // MARK: lower third — kicker · serif title · summary · quick note · CTA

    private var lowerThird: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text(kicker.uppercased())
                    .font(.inter(11, .semibold)).kerning(1.5)
                    .foregroundStyle(Nuru.gold)
                Text(title)
                    .font(.fraunces(30, .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.nBodyLg)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(3)
                }
                if let quickNote, !quickNote.isEmpty {
                    HStack(spacing: 6) {
                        Icon(.penLine, size: 12, color: Nuru.gold)
                        Text(quickNote)
                            .font(.inter(12, .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Nuru.S.screen)
            .gentleEntrance()

            startWatchingButton
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.lg)
                .padding(.bottom, Nuru.S.xl)
                .gentleEntrance(delay: 0.08)
        }
    }

    private var startWatchingButton: some View {
        Button {
            Haptics.action()
            playing = true
        } label: {
            HStack(spacing: Nuru.S.sm) {
                Icon(.play, size: 16, color: Nuru.navy)
                Text("Start watching")
                    .font(.inter(16, .bold))
                    .foregroundStyle(Nuru.navy)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Nuru.buttonHeightLg)
            .background(Nuru.white, in: Capsule())
        }
        .buttonStyle(.pressable)
    }

    // MARK: top-left circular ✕

    private var closeButton: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Icon(.x, size: 18, color: .white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.pressable)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, Nuru.S.sm)
            Spacer(minLength: 0)
        }
    }
}
