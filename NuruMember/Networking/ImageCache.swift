// Image + HTTP caching for a lightning-fast, lag-free feed.
//
// The member app is image-heavy (hero cards, welcome video thumbs, avatars,
// event/plan/announcement art). SwiftUI's stock `AsyncImage` keeps no cache of
// its own: every time a cell scrolls back into view — or the user returns to a
// screen — it re-downloads AND re-decodes the bitmap, which shows as flicker and
// burns bandwidth. `CachedAsyncImage` is an API-compatible drop-in that adds two
// cache layers:
//   1. a process-wide in-memory cache of *decoded* `UIImage`s (instant, no
//      re-decode, no flicker), and
//   2. the shared on-disk `URLCache` (survives relaunch, no re-download),
// so a given URL is fetched + decoded at most once per cold start.
import SwiftUI
import UIKit
import ImageIO

/// Process-wide cache of decoded images, sized by pixel cost. Sits on top of the
/// disk `URLCache` so repeat appearances are an O(1) dictionary hit.
final class NuruImageCache {
    static let shared = NuruImageCache()
    private let memory = NSCache<NSURL, UIImage>()

    private init() {
        memory.totalCostLimit = 96 * 1024 * 1024 // ~96 MB of decoded pixels
        memory.countLimit = 400
    }

    func image(for url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func insert(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4
        memory.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

/// Size the shared HTTP cache generously and wire it before any request runs.
/// Image loads go through `URLSession.shared`, and the API client's dedicated
/// session points at `URLCache.shared` too — so both share this one disk cache.
func configureNuruCaches() {
    URLCache.shared = URLCache(
        memoryCapacity: 32 * 1024 * 1024,   // 32 MB
        diskCapacity: 350 * 1024 * 1024,    // 350 MB
        directory: nil
    )
}

/// Drop-in replacement for `AsyncImage(url:) { phase in … }`. Same phase-closure
/// signature, so call sites only change the type name. Resolves instantly from
/// the in-memory cache when warm; otherwise loads via the disk-cached session and
/// decodes off the main actor.
struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let scale: CGFloat
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(url: URL?, scale: CGFloat = 1, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.scale = scale
        self.content = content
    }

    var body: some View {
        content(phase)
            // Re-runs (and cancels the prior load) whenever the URL changes; a
            // synchronous warm-cache hit avoids a one-frame placeholder flash.
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { phase = .empty; return }

        if let cached = NuruImageCache.shared.image(for: url) {
            phase = .success(Image(uiImage: cached))
            return
        }

        do {
            var req = URLRequest(url: url)
            req.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: req)
            try Task.checkCancellation()
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                phase = .failure(URLError(.badServerResponse))
                return
            }
            guard let image = await Self.decode(data, scale: scale) else {
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }
            NuruImageCache.shared.insert(image, for: url)
            phase = .success(Image(uiImage: image))
        } catch is CancellationError {
            // view scrolled away mid-flight — leave the last phase as-is
        } catch {
            phase = .failure(error)
        }
    }

    /// Decode off the main actor so large hero images never hitch the UI.
    private static func decode(_ data: Data, scale: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            // Downsample oversized originals at decode time (ImageIO thumbnail
            // API) so a huge camera upload never inflates to a full-size bitmap
            // in memory — 2400px covers 2x/3x hero cards with room to spare.
            let maxPixels: CGFloat = 2400
            if let src = CGImageSourceCreateWithData(data as CFData, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
               let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
               let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
               max(w, h) > maxPixels {
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                    kCGImageSourceCreateThumbnailWithTransform: true, // bake in EXIF orientation
                    kCGImageSourceShouldCacheImmediately: true,       // decode now, off-main
                ]
                if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                    return UIImage(cgImage: cg, scale: scale, orientation: .up)
                }
            }
            return UIImage(data: data, scale: scale)
        }.value
    }
}
