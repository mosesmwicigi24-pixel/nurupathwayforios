// WhatsApp-style image experience, shared by chat bubbles and the event wall.
// `NaturalImageThumb` renders a modest in-feed thumbnail at the image's OWN
// aspect (measured from the decoded bitmap, clamped so extreme panoramas /
// towers stay tidy) and opens `ImageLightbox` on tap — a black full-screen
// viewer that fits the image to the phone (scaledToFit) with pinch-to-zoom
// (1x–4x), drag-to-pan while zoomed, double-tap 1x/2.5x, and swipe-down or a
// top-left ✕ to dismiss. Structs are deliberately small and self-contained.
import SwiftUI
import UIKit

// MARK: - Natural-aspect thumbnail (tap → lightbox)

struct NaturalImageThumb: View {
    let url: URL?
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let minAspect: CGFloat
    let maxAspect: CGFloat
    let cornerRadius: CGFloat
    /// Optional host double-tap (chat's ❤️ reaction). Declared BEFORE the single
    /// tap so SwiftUI disambiguates: two quick taps react, one tap opens.
    let onDoubleTap: (() -> Void)?

    @State private var aspect: CGFloat?
    @State private var showLightbox = false

    init(url: URL?,
         maxWidth: CGFloat = 240,
         maxHeight: CGFloat = 480,
         minAspect: CGFloat = 0.5,
         maxAspect: CGFloat = 2.0,
         cornerRadius: CGFloat = 12,
         onDoubleTap: (() -> Void)? = nil) {
        self.url = url
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.minAspect = minAspect
        self.maxAspect = maxAspect
        self.cornerRadius = cornerRadius
        self.onDoubleTap = onDoubleTap
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        tappable
            .fullScreenCover(isPresented: $showLightbox) { ImageLightbox(url: url) }
    }

    // Only mount the double-tap recognizer when the host wants one, so plain
    // thumbs (event wall) open on the very first tap with no disambiguation lag.
    @ViewBuilder private var tappable: some View {
        if let onDoubleTap {
            frameContent
                .onTapGesture(count: 2, perform: onDoubleTap)
                .onTapGesture { open() }
        } else {
            frameContent
                .onTapGesture { open() }
        }
    }

    private func open() {
        if url != nil { showLightbox = true }
    }

    /// The frame carries the (clamped) natural aspect; 4:3 until measured.
    private var frameContent: some View {
        Color.clear
            .aspectRatio(aspect ?? 4.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: maxWidth, maxHeight: maxHeight)
            .overlay(imageContent)
            .clipShape(shape)
            .contentShape(shape)
    }

    @ViewBuilder private var imageContent: some View {
        if let url {
            CachedAsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                        .onAppear { measure() }
                } else if phase.error != nil {
                    ThumbPlaceholder()
                } else {
                    ZStack { ThumbPlaceholder(); ProgressView().tint(Nuru.gold) }
                }
            }
        } else {
            ThumbPlaceholder()
        }
    }

    /// By the time the `.success` branch renders, the decoded bitmap is in
    /// `NuruImageCache` — read its size once and let the frame adopt the aspect.
    private func measure() {
        guard aspect == nil, let url,
              let ui = NuruImageCache.shared.image(for: url),
              ui.size.width > 0, ui.size.height > 0 else { return }
        aspect = min(max(ui.size.width / ui.size.height, minAspect), maxAspect)
    }
}

private struct ThumbPlaceholder: View {
    var body: some View {
        Rectangle().fill(Color(hex: 0x0B1F33, alpha: 0.05))
            .overlay(Icon(.image, size: 26, color: Color(hex: 0x9AA3AF)))
    }
}

// MARK: - Full-screen lightbox

struct ImageLightbox: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss

    init(url: URL?) { self.url = url }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            LightboxZoomImage(url: url) { dismiss() }
            closeButton
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Icon(.x, size: 18, color: .white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.top, 8)
    }
}

/// The fitted image plus all viewer gestures. Pinch (anchored at center) zooms
/// 1x–4x; dragging pans while zoomed and pulls-to-dismiss at 1x; double-tap
/// toggles 1x/2.5x. No scroll view lives underneath, so nothing competes.
private struct LightboxZoomImage: View {
    let url: URL?
    var onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var dismissDrag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            fitted
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(x: offset.width, y: offset.height + dismissDrag)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { toggleZoom() }
                .gesture(drag(geo.size).simultaneously(with: magnify(geo.size)))
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var fitted: some View {
        if let url {
            CachedAsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFit()
                } else if phase.error != nil {
                    Icon(.image, size: 34, color: .white.opacity(0.4))
                } else {
                    ProgressView().tint(.white)
                }
            }
        } else {
            Icon(.image, size: 34, color: .white.opacity(0.4))
        }
    }

    private func magnify(_ size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { v in
                scale = min(max(baseScale * v, 1), 4)
            }
            .onEnded { _ in
                baseScale = scale
                if scale <= 1.01 { resetZoom() } else { settle(size) }
            }
    }

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { v in
                if scale > 1 {
                    offset = CGSize(width: baseOffset.width + v.translation.width,
                                    height: baseOffset.height + v.translation.height)
                } else {
                    dismissDrag = max(0, v.translation.height)
                }
            }
            .onEnded { v in
                if scale > 1 {
                    baseOffset = offset
                    settle(size)
                } else if dismissDrag > 110 || v.predictedEndTranslation.height > 240 {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dismissDrag = 0
                    }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if scale > 1 {
                scale = 1; baseScale = 1
                offset = .zero; baseOffset = .zero
            } else {
                scale = 2.5; baseScale = 2.5
            }
        }
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            scale = 1; baseScale = 1
            offset = .zero; baseOffset = .zero
        }
    }

    /// Spring the pan back inside the zoomed image's bounds after a gesture.
    private func settle(_ size: CGSize) {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            offset.width = min(max(offset.width, -maxX), maxX)
            offset.height = min(max(offset.height, -maxY), maxY)
        }
        baseOffset = offset
    }
}
