// FitImage — a remote image that sizes itself to the picture's NATURAL aspect
// ratio, so cards grow to fit their media instead of cropping it into a fixed
// box. Renders through the existing CachedAsyncImage; once the bitmap lands in
// NuruImageCache we read its pixel dimensions and animate the container from
// the 16:9 loading placeholder to the true aspect (clamped to 0.5…2.2 so a
// panorama or a full-length portrait can't blow up the layout). Failure / no
// URL shows a branded gradient — never a blank gray slab.
//
// Two sizing modes:
//   • width-driven (default): fills the container width, height = width/aspect
//     — for card covers and heroes.
//   • `fixedHeight`: height is pinned and the WIDTH follows the aspect —
//     for horizontal gallery rails.
import SwiftUI

struct FitImage: View {
    let url: URL?
    /// Aspect (w/h) used while the image loads. 16:9 by default.
    var placeholderAspect: CGFloat = 16.0 / 9.0
    /// When set, the image is `fixedHeight` tall and its width tracks the aspect.
    var fixedHeight: CGFloat? = nil
    /// Branded stand-in for loading/failure (defaults to the hero gradient).
    var fallback: LinearGradient = Nuru.heroGradient
    /// Reports the measured (clamped) aspect — lets a card reuse it elsewhere,
    /// e.g. the welcome video keeps its poster's shape while playing.
    var onAspect: ((CGFloat) -> Void)? = nil

    @State private var measured: CGFloat?

    /// Sane clamps so extreme originals can't wreck the feed.
    static let aspectRange: ClosedRange<CGFloat> = 0.5...2.2

    private var aspect: CGFloat { measured ?? placeholderAspect }

    var body: some View {
        if let h = fixedHeight {
            layer
                .frame(width: h * aspect, height: h)
                .clipped()
        } else {
            // An aspect-shaped clear box sets the size (container width ×
            // natural height); the image fills it exactly — once measured the
            // box IS the image's shape, so "fill" means no crop and no bars.
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay { layer }
                .clipped()
        }
    }

    @ViewBuilder
    private var layer: some View {
        if let url {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                        .onAppear { measure(url) }
                case .failure:
                    fallback
                default:
                    fallback.opacity(0.55).nuruShimmer()   // softer + alive while loading
                }
            }
        } else {
            fallback
        }
    }

    /// The decoded UIImage is already in the in-memory cache by the time the
    /// phase flips to .success — read its dimensions from there (the phase
    /// itself only exposes a SwiftUI `Image`).
    private func measure(_ url: URL) {
        guard measured == nil, let ui = NuruImageCache.shared.image(for: url) else { return }
        guard ui.size.width > 0, ui.size.height > 0 else { return }
        let a = Self.clamp(ui.size.width / ui.size.height)
        withAnimation(.easeOut(duration: 0.25)) { measured = a }
        onAspect?(a)
    }

    static func clamp(_ aspect: CGFloat) -> CGFloat {
        min(max(aspect, aspectRange.lowerBound), aspectRange.upperBound)
    }
}
