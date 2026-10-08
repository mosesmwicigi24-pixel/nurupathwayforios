// The featured video takes its own shape (owner, 2026-10-06). A portrait
// video sat pillarboxed inside Home's fixed 16:9 frame. The frame is now the
// video's: the card's content width, and a height of width × (height ÷
// width), the ratio clamped to 9:20…21:9. The picture fills that frame, so
// the player draws no bars. A portrait video makes the card taller, and
// that's wanted.
//
// Where the shape comes from, as each arrives:
//   1. the ratio remembered for this media asset from an earlier load, so the
//      first paint is already right;
//   2. the thumbnail's pixel size once it loads (the server's thumbnail, or
//      the poster frame cut from the video when it has none);
//   3. the video itself: its track's naturalSize turned by its
//      preferredTransform, as absolute values. An iPhone portrait clip is
//      often stored landscape with a 90° turn. This is the truth, and it is
//      remembered.
// Before any of them, 16:9.
//
// YouTube and Vimeo keep 16:9: their embedded players draw their own frame,
// and their thumbnails can carry bars of their own (YouTube's hqdefault is a
// 4:3 picture around a 16:9 one), so neither says the video's shape.
import SwiftUI
import AVFoundation

enum VideoShape {
    /// Width ÷ height before anything is known.
    static let standard: CGFloat = 16.0 / 9.0
    /// The narrowest frame (9:20) and the widest (21:9).
    static let narrowest: CGFloat = 9.0 / 20.0
    static let widest: CGFloat = 21.0 / 9.0

    static func clamp(_ ratio: CGFloat) -> CGFloat { min(max(ratio, narrowest), widest) }

    /// A size's width ÷ height, clamped; nil for a size with no area.
    static func ratio(_ size: CGSize) -> CGFloat? {
        let w = abs(size.width), h = abs(size.height)
        guard w.isFinite, h.isFinite, w > 0, h > 0 else { return nil }
        return clamp(w / h)
    }

    /// What the eye sees: the stored size turned by the track's transform,
    /// as absolute values (1920×1080 turned 90° is 1080×1920).
    static func displaySize(natural: CGSize, transform: CGAffineTransform) -> CGSize {
        let r = CGRect(origin: .zero, size: natural).applying(transform)
        return CGSize(width: abs(r.width), height: abs(r.height))
    }

    /// Whether the app reads this source's own pixels. An embed's player
    /// keeps its own 16:9 frame.
    static func learnsShape(source: String) -> Bool {
        !["youtube", "vimeo"].contains(source.lowercased())
    }

    /// The frame from what is known so far: the video's own shape (measured,
    /// or remembered from an earlier load), else its thumbnail's, else 16:9.
    static func resolve(video: CGFloat?, thumbnail: CGFloat?) -> CGFloat {
        video ?? thumbnail ?? standard
    }
}

/// Each featured video's measured shape, remembered across launches by its
/// media asset id, so the card's first paint already has the right frame.
@MainActor
final class VideoShapeStore: ObservableObject {
    static let shared = VideoShapeStore()

    private let defaults: UserDefaults
    @Published private var measured: [String: CGFloat] = [:]
    private var measuring: Set<String> = []

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static func key(_ id: String) -> String { "nuru.videoShape.\(id)" }

    /// The video's own shape: measured this session, else remembered.
    func ratio(for id: String) -> CGFloat? {
        guard !id.isEmpty else { return nil }
        if let r = measured[id] { return r }
        let stored = defaults.double(forKey: Self.key(id))
        return stored > 0 ? VideoShape.clamp(CGFloat(stored)) : nil
    }

    func remember(_ ratio: CGFloat, for id: String) {
        guard !id.isEmpty, ratio.isFinite, ratio > 0 else { return }
        let r = VideoShape.clamp(ratio)
        measured[id] = r
        defaults.set(Double(r), forKey: Self.key(id))
    }

    /// Measure the video once a session (a remembered shape is checked again,
    /// in case the file was replaced). Silent when the video can't be read —
    /// an HLS stream has no track size before it plays — and the frame keeps
    /// what it had.
    func measure(_ urlString: String, id: String) async {
        guard !id.isEmpty, measured[id] == nil, !measuring.contains(id),
              let url = URL(string: urlString) else { return }
        measuring.insert(id)
        defer { measuring.remove(id) }
        if let size = await Self.displaySize(of: url), let r = VideoShape.ratio(size) {
            remember(r, for: id)
        }
    }

    /// The first video track's display size: naturalSize through
    /// preferredTransform.
    nonisolated static func displaySize(of url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let loaded = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        return VideoShape.displaySize(natural: loaded.0, transform: loaded.1)
    }
}
