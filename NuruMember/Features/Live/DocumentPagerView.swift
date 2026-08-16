// Nuru Live "Broadcast Studio" — Document source: a PDF picked from Files,
// rendered page-by-page via PDFKit into plain UIImages, and paged full-screen
// with a SwiftUI `TabView`. This exact view — not a hidden off-screen
// buffer — is what's on screen while document mode is active, because
// ReplayKit's in-app capture (AppScreenCapture) records whatever this app is
// actually rendering to its window; there's no separate "export" path.
import PDFKit
import SwiftUI

/// Loads a picked PDF and rasterizes every page to a UIImage the pager can
/// show instantly (no per-page PDFKit re-render on each swipe, no vector
/// scaling jank while ReplayKit is capturing). Rendered at 2× the device's
/// point width so text stays crisp on a Pro Max-class screen without
/// wasting memory on an arbitrarily huge PDF.
@MainActor
final class DocumentSource: ObservableObject {
    @Published private(set) var title: String = ""
    @Published private(set) var pages: [UIImage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    /// Reads the security-scoped URL (`UIDocumentPickerViewController`/
    /// `.fileImporter` hand back an out-of-sandbox URL) and rasterizes every
    /// page off the main thread. Access is started/stopped around the read —
    /// PDFKit itself needs the bytes, not a lingering scope.
    func load(from url: URL) async {
        isLoading = true
        loadError = nil
        pages = []
        title = url.deletingPathExtension().lastPathComponent

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url), let document = PDFDocument(data: data) else {
            loadError = "Couldn't open that PDF."
            isLoading = false
            return
        }
        let targetWidth = UIScreen.main.bounds.width * 2
        let rendered = await Task.detached(priority: .userInitiated) {
            (0..<document.pageCount).compactMap { i -> UIImage? in
                guard let page = document.page(at: i) else { return nil }
                let bounds = page.bounds(for: .mediaBox)
                guard bounds.width > 0, bounds.height > 0 else { return nil }
                let scale = targetWidth / bounds.width
                let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                let renderer = UIGraphicsImageRenderer(size: size)
                return renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                    ctx.cgContext.translateBy(x: 0, y: size.height)
                    ctx.cgContext.scaleBy(x: scale, y: -scale)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
            }
        }.value
        pages = rendered
        isLoading = false
        if rendered.isEmpty { loadError = "That PDF had no readable pages." }
    }

    func reset() {
        pages = []
        title = ""
        loadError = nil
    }
}

/// Full-bleed swipeable pager — this IS the broadcast surface while document
/// mode is active (camera preview is detached; see BroadcastController.
/// selectDocument). Page dots + a page counter give the broadcaster (and, via
/// the captured stream, viewers) their place without any chrome that would
/// look out of place recorded full-screen.
struct DocumentPagerView: View {
    @ObservedObject var source: DocumentSource
    @Binding var pageIndex: Int

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !source.pages.isEmpty {
                TabView(selection: $pageIndex) {
                    ForEach(Array(source.pages.enumerated()), id: \.offset) { i, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(.horizontal, 6)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
        }
    }
}
