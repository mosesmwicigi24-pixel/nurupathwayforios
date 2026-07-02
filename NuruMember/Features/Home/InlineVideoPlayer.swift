// Plays a video INSIDE the view that hosts it — it never bounces out to Safari.
// YouTube / Vimeo load as inline embeds in a WKWebView (playsinline, so iOS
// doesn't hijack into the fullscreen player); direct/cloudinary URLs load as an
// inline HTML5 <video>. Originally built for the Home welcome card; generalised
// so VideoPlayerPage (the universal full-bleed player) can reuse the exact same
// embed logic for announcement/event videos.
import SwiftUI
import WebKit

struct InlineVideoPlayer: UIViewRepresentable {
    let urlString: String?
    let source: String               // cloudinary | youtube | vimeo | direct | private
    let externalVideoId: String?
    /// Fires once when the embed's page finishes (or fails) loading — hosts use
    /// it to drop their buffering spinner. Optional, so call sites are unchanged.
    var onReady: (() -> Void)?

    /// The Home welcome-video payload, unchanged call sites.
    init(video: WelcomeVideo, onReady: (() -> Void)? = nil) {
        self.urlString = video.playUrl
        self.source = video.videoSource
        self.externalVideoId = video.externalVideoId
        self.onReady = onReady
    }

    /// Any raw video URL (announcements, events). When `source` is nil the
    /// provider is sniffed from the URL's host (youtube/vimeo/direct).
    init(urlString: String?, source: String? = nil, externalVideoId: String? = nil, onReady: (() -> Void)? = nil) {
        self.urlString = urlString
        self.source = source ?? Self.detectSource(urlString)
        self.externalVideoId = externalVideoId
        self.onReady = onReady
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []   // allow autoplay after the tap
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onReady = onReady
        guard !context.coordinator.loaded else { return }
        context.coordinator.loaded = true
        if let embed = embedURL {
            web.load(URLRequest(url: embed))
        } else if let raw = urlString, let u = URL(string: raw) {
            web.loadHTMLString(Self.html(for: u), baseURL: nil)
        } else {
            // Nothing playable — never leave the host spinning forever.
            context.coordinator.signalReady()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded = false
        var onReady: (() -> Void)?

        /// Fire the host's ready callback exactly once (finish OR failure both
        /// mean "stop showing the spinner"; the web view shows its own errors).
        func signalReady() {
            onReady?()
            onReady = nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { signalReady() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { signalReady() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { signalReady() }
    }

    /// Best-effort provider detection for URLs that arrive without a source tag.
    static func detectSource(_ raw: String?) -> String {
        guard let raw, let host = URLComponents(string: raw)?.host?.lowercased() else { return "direct" }
        if host.contains("youtube.com") || host.contains("youtu.be") { return "youtube" }
        if host.contains("vimeo.com") { return "vimeo" }
        return "direct"
    }

    /// A player-page URL for the sources that require one (YouTube, Vimeo).
    private var embedURL: URL? {
        switch source.lowercased() {
        case "youtube":
            guard let id = youTubeId else { return nil }
            return URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1&autoplay=1&modestbranding=1&rel=0")
        case "vimeo":
            guard let id = externalVideoId ?? Self.lastPathComponent(urlString) else { return nil }
            return URL(string: "https://player.vimeo.com/video/\(id)?autoplay=1&playsinline=1")
        default:
            return nil   // direct / cloudinary / private → HTML5 <video>
        }
    }

    private var youTubeId: String? {
        if let id = externalVideoId, !id.isEmpty { return id }
        // Fallback: pull ?v= or the youtu.be path from the external URL.
        guard let raw = urlString, let comps = URLComponents(string: raw) else { return nil }
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
        <style>html,body{margin:0;background:#000;height:100%}video{width:100%;height:100%;object-fit:contain}</style>
        </head><body>
        <video src='\(url.absoluteString)' controls autoplay playsinline webkit-playsinline></video>
        </body></html>
        """
    }
}
