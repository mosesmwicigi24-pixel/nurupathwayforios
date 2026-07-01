// Plays the Home welcome video INSIDE its card — it never bounces out to Safari.
// YouTube / Vimeo load as inline embeds in a WKWebView (playsinline, so iOS
// doesn't hijack into the fullscreen player); direct/cloudinary URLs load as an
// inline HTML5 <video>. The web view is pinned to the card's 16:9 box.
import SwiftUI
import WebKit

struct InlineVideoPlayer: UIViewRepresentable {
    let video: WelcomeVideo

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []   // allow autoplay after the tap
        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard !context.coordinator.loaded else { return }
        context.coordinator.loaded = true
        if let embed = embedURL {
            web.load(URLRequest(url: embed))
        } else if let raw = video.playUrl, let u = URL(string: raw) {
            web.loadHTMLString(Self.html(for: u), baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loaded = false }

    /// A player-page URL for the sources that require one (YouTube, Vimeo).
    private var embedURL: URL? {
        switch video.videoSource.lowercased() {
        case "youtube":
            guard let id = youTubeId else { return nil }
            return URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1&autoplay=1&modestbranding=1&rel=0")
        case "vimeo":
            guard let id = video.externalVideoId ?? Self.lastPathComponent(video.playUrl) else { return nil }
            return URL(string: "https://player.vimeo.com/video/\(id)?autoplay=1&playsinline=1")
        default:
            return nil   // direct / cloudinary / private → HTML5 <video>
        }
    }

    private var youTubeId: String? {
        if let id = video.externalVideoId, !id.isEmpty { return id }
        // Fallback: pull ?v= or the youtu.be path from the external URL.
        guard let raw = video.playUrl, let comps = URLComponents(string: raw) else { return nil }
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        return Self.lastPathComponent(raw)
    }

    private static func lastPathComponent(_ raw: String?) -> String? {
        guard let raw, let u = URL(string: raw) else { return nil }
        let last = u.lastPathComponent
        return last.isEmpty ? nil : last
    }

    private static func html(for url: URL) -> String {
        """
        <html><head><meta name='viewport' content='width=device-width, initial-scale=1'>
        <style>html,body{margin:0;background:#000;height:100%}video{width:100%;height:100%;object-fit:cover}</style>
        </head><body>
        <video src='\(url.absoluteString)' controls autoplay playsinline webkit-playsinline></video>
        </body></html>
        """
    }
}
