// Nuru Live "Broadcast Studio" — the source-switcher sheet opened from
// GoLiveBroadcastView's controls row: Camera (default) / Document (PDF
// pager) / Screen (this app's screen, ReplayKit in-app capture). See
// AppScreenCapture.swift and DocumentPagerView.swift for the capture/render
// mechanics; this file is presentation only.
import SwiftUI
import UniformTypeIdentifiers

struct BroadcastSourceSheet: View {
    @ObservedObject var controller: BroadcastController
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.22)).frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 16)
            Text("Broadcast source")
                .font(.fraunces(17, .semibold)).foregroundStyle(.white)
                .padding(.bottom, 16)
            VStack(spacing: 10) {
                sourceRow(
                    icon: "camera.fill", title: "Camera", subtitle: "Your live camera feed",
                    selected: controller.videoSource == .camera
                ) {
                    Haptics.tap()
                    Task { await controller.selectCamera() }
                    dismiss()
                }
                sourceRow(
                    icon: "doc.richtext.fill", title: "Document", subtitle: "Share a PDF, page by page",
                    selected: controller.videoSource == .document
                ) {
                    Haptics.tap()
                    showFileImporter = true
                }
                sourceRow(
                    icon: "rectangle.on.rectangle", title: "Share my screen (this app)",
                    subtitle: "Viewers see whatever you show in Nuru — mic stays live",
                    selected: controller.videoSource == .screen
                ) {
                    Haptics.tap()
                    Task { await controller.selectScreen() }
                    dismiss()
                }
            }
            .padding(.horizontal, 18)
            if let error = controller.sourceError {
                Text(error)
                    .font(.inter(12)).foregroundStyle(Color(hex: 0xF87171))
                    .multilineTextAlignment(.center)
                    .padding(.top, 14).padding(.horizontal, 24)
            }
            Spacer(minLength: 12)
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Nuru.navyDeep)
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            Task { await controller.selectDocument(url: url) }
            dismiss()
        }
    }

    private func sourceRow(icon: String, title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Nuru.navy : .white)
                    .frame(width: 40, height: 40)
                    .background(selected ? Nuru.gold : Color.white.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.inter(14, .semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.inter(11)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 6)
                if selected {
                    Icon(.checkCircle2, size: 18, color: Nuru.gold)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.white.opacity(selected ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressableSubtle)
    }
}
