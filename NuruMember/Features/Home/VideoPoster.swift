// The poster the server never sent (owner, 2026-08-26: "the thumbnail in the
// Nuru Pathway featured should be displayed").
//
// Uploaded (direct/hosted) videos carry no thumbnail_url — there is no ffmpeg
// on the API host to cut one, so the card showed a flat grey box. The frame we
// need is already inside the video: AVAssetImageGenerator pulls one ~1s in,
// off the main actor, and we keep it for the session so the card paints
// instantly on every later appearance. YouTube/Vimeo keep their provider
// thumbnails (derived server-side) and never reach this path.
import SwiftUI
import AVFoundation

@MainActor
final class VideoPosterCache: ObservableObject {
    static let shared = VideoPosterCache()
    private var images: [String: UIImage] = [:]
    private var inFlight: Set<String> = []

    func poster(for urlString: String) -> UIImage? { images[urlString] }

    /// Cut a poster frame once per URL per session. Silent on failure — the
    /// card simply keeps its neutral placeholder, exactly as before.
    func load(_ urlString: String) async {
        guard images[urlString] == nil, !inFlight.contains(urlString),
              let url = URL(string: urlString) else { return }
        inFlight.insert(urlString)
        defer { inFlight.remove(urlString) }
        let image = await Self.frame(from: url)
        if let image { images[urlString] = image }
    }

    private static func frame(from url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) { () -> UIImage? in
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 1280, height: 720)
            // A frame a second in: past any black/fade-in first frame.
            let at = CMTime(seconds: 1, preferredTimescale: 600)
            if #available(iOS 16.0, *) {
                guard let cg = try? await gen.image(at: at).image else { return nil }
                return UIImage(cgImage: cg)
            }
            guard let cg = try? gen.copyCGImage(at: at, actualTime: nil) else { return nil }
            return UIImage(cgImage: cg)
        }.value
    }
}
