// Stylus drawing for Selah — PencilKit, gated to Apple-Pencil-capable devices
// (iPad; Apple Pencil doesn't exist for iPhone, so the toolbar entry point
// itself is hidden there rather than offering a dead end). A drawing exports
// to a PNG and uploads through the SAME chat/attachments sign→Cloudinary flow
// the app already uses for voice notes and images (MemberAPI.signChatAttachment
// + uploadChatAttachment) — this module never invents its own upload path.
import SwiftUI
import PencilKit

/// True on iPad (the only Nuru form factor with Apple Pencil support). Gates
/// the "Draw" toolbar entry point everywhere in Selah.
let isPenCapableDevice: Bool = UIDevice.current.userInterfaceIdiom == .pad

struct PKCanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var onChange: () -> Void = {}

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput // Pencil preferred; finger still works
        canvasView.backgroundColor = .white
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvasView.delegate = context.coordinator
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            PKToolPicker.shared(for: window)?.setVisible(true, forFirstResponder: canvasView)
            PKToolPicker.shared(for: window)?.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }
        return canvasView
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: PKCanvasRepresentable
        init(_ parent: PKCanvasRepresentable) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { parent.onChange() }
    }
}

/// Full-screen pen page: draw → Save uploads a PNG and hands back the
/// delivered secure_url; Cancel discards. Presented from SelahEditorView.
struct SelahDrawingSheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvasView = PKCanvasView()
    @State private var hasStrokes = false
    @State private var uploading = false
    @State private var uploadError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Text("Cancel").font(.inter(14, .semibold)).foregroundStyle(Color(hex: 0x59667C))
                }
                Spacer(minLength: 0)
                Text("Draw").font(.fraunces(17, .medium)).foregroundStyle(Nuru.navy)
                Spacer(minLength: 0)
                Button { Haptics.tap(); canvasView.drawing = PKDrawing(); hasStrokes = false } label: {
                    Text("Clear").font(.inter(14, .semibold)).foregroundStyle(Color(hex: 0x59667C))
                }
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.vertical, Nuru.S.md)

            PKCanvasRepresentable(canvasView: $canvasView) {
                hasStrokes = !canvasView.drawing.strokes.isEmpty
            }
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 0).stroke(Nuru.border, lineWidth: 1))

            if let uploadError {
                Text(uploadError).font(.inter(11, .medium)).foregroundStyle(Color(hex: 0xB91C1C))
                    .padding(.horizontal, Nuru.S.screen).padding(.top, Nuru.S.sm)
            }

            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 8) {
                    if uploading { ProgressView().tint(.white) }
                    Text(uploading ? "Saving…" : "Save drawing")
                        .font(.inter(14, .bold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: 0xC9A227), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(!hasStrokes || uploading)
            .opacity(hasStrokes ? 1 : 0.5)
            .padding(Nuru.S.screen)
        }
        .background(Nuru.paper.ignoresSafeArea())
    }

    private func save() async {
        guard hasStrokes, !uploading else { return }
        uploading = true
        uploadError = nil
        let bounds = canvasView.drawing.bounds.insetBy(dx: -12, dy: -12)
        let image = canvasView.drawing.image(from: bounds.isEmpty ? canvasView.bounds : bounds, scale: UIScreen.main.scale)
        guard let png = image.pngData() else {
            uploading = false
            uploadError = "Couldn't render that drawing. Try again."
            return
        }
        do {
            let sign = try await MemberAPI.signChatAttachment(contentType: "image/png", kind: "image")
            let url = try await MemberAPI.uploadChatAttachment(sign: sign, data: png, filename: "selah-drawing.png", contentType: "image/png")
            uploading = false
            Haptics.success()
            onSave(url)
            dismiss()
        } catch {
            uploading = false
            uploadError = (error as? APIError)?.errorDescription ?? "Couldn't save the drawing. Try again."
        }
    }
}
