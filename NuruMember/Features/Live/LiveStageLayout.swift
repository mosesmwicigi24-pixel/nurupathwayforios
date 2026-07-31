// Nuru Live — pure Zoom-style stage geometry, shared by BOTH halves of the
// stage: LiveStageCompositor (the actual composited broadcast frame, in
// canvas points — e.g. 1080x1920) and LiveStageView (the host's own local
// SwiftUI preview, in screen points). Neither one re-derives its own
// layout math; both call into this file with their own canvas size, so the
// two literally cannot drift apart — same inputs, same rects, by
// construction. That's what "the host's own preview must match what
// viewers receive" means in practice for a hand-rolled offscreen
// compositor with no shared rendering pipeline.
//
// One full-bleed MAIN tile (whoever's spotlighted) + a vertical rail of
// thumbnails down the right edge for everyone else — task spec: "~22% of
// canvas width", "stack without overflowing — shrink ... never clip."
import CoreGraphics

enum LiveStageLayout {
    /// Rail tile width as a fraction of canvas width.
    static let railWidthFraction: CGFloat = 0.22
    /// Rail tile aspect ratio (width / height) — a portrait-ish self-view
    /// tile, matching Zoom's own mobile rail tiles.
    static let railAspectRatio: CGFloat = 0.75
    static let marginFraction: CGFloat = 0.03
    static let spacingFraction: CGFloat = 0.018
    static let cornerRadiusFraction: CGFloat = 0.05

    /// The full-bleed main tile — always the ENTIRE canvas, whoever is
    /// currently spotlighted. A function (not just callers writing
    /// `CGRect(origin: .zero, size: canvas)` inline) so every call site
    /// reads as an intentional "this is the main tile", and so the
    /// "identical geometry regardless of guest count" invariant has one
    /// place it's defined.
    static func mainRect(canvas: CGSize) -> CGRect {
        CGRect(origin: .zero, size: canvas)
    }

    /// One rect per rail slot, top-to-bottom down the right edge, in the
    /// SAME order `count` implies callers pass their tracks (host first,
    /// then guests in join order — see LiveStageCompositor.participants).
    /// Shrinks every tile uniformly — never overlaps, never clips, never
    /// scrolls — if the ideal size for `count` tiles would overflow the
    /// canvas height.
    static func railRects(count: Int, canvas: CGSize) -> [CGRect] {
        guard count > 0, canvas.width > 0, canvas.height > 0 else { return [] }
        let margin = canvas.width * marginFraction
        let spacing = canvas.width * spacingFraction
        let idealWidth = canvas.width * railWidthFraction
        let idealHeight = idealWidth / railAspectRatio
        let available = max(canvas.height - margin * 2, 0)
        let idealTotal = CGFloat(count) * idealHeight + CGFloat(count - 1) * spacing
        // Scale height, width AND spacing together (not just the tile) —
        // scaling only the tile while leaving spacing fixed can still push
        // the total past `available` once spacing dominates at count=6.
        let scale = idealTotal > available ? available / idealTotal : 1
        let height = idealHeight * scale
        let width = idealWidth * scale
        let actualSpacing = spacing * scale
        let totalHeight = CGFloat(count) * height + CGFloat(max(count - 1, 0)) * actualSpacing
        let startY = margin + max(available - totalHeight, 0) / 2
        let x = canvas.width - margin - width
        return (0..<count).map { index in
            CGRect(
                x: x,
                y: startY + CGFloat(index) * (height + actualSpacing),
                width: width,
                height: height
            )
        }
    }

    static func cornerRadius(canvas: CGSize) -> CGFloat {
        min(canvas.width, canvas.height) * cornerRadiusFraction
    }
}
