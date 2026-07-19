// Selah's quiet page — the rich-text + pen editor for one thought. New-or-
// existing, always full screen (this is the "write what's on your heart"
// surface, not a quick sheet). Bold/italic/color/font persist per span
// (ThoughtSpan); line spacing is a global preference (see SelahRichEditor.swift
// header note); drawings upload via the existing chat/attachments flow and are
// attached as `drawing_urls`.
import SwiftUI

/// A new-or-existing thought being edited.
struct SelahDraft: Identifiable {
    let thoughtId: String
    let isNew: Bool
    var title: String
    var body: String
    var spans: [ThoughtSpan]
    var drawingUrls: [String]
    var id: String { thoughtId }

    init() { thoughtId = UUID().uuidString; isNew = true; title = ""; body = ""; spans = []; drawingUrls = [] }
    init(_ t: Thought) {
        thoughtId = t.thoughtId; isNew = false
        title = t.title ?? ""; body = t.body; spans = t.bodySpans ?? []; drawingUrls = t.drawingUrls
    }
}

struct SelahEditorView: View {
    @State var draft: SelahDraft
    let onSave: (SelahDraft) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = RichEditorController()
    @AppStorage("nuru.selah.lineSpacing") private var spacingRaw = SelahSpacing.comfortable.rawValue
    @State private var liveAttributed: NSAttributedString
    @State private var showDrawing = false
    @State private var showFontMenu = false
    @State private var showColorMenu = false
    @State private var pendingDelete = false

    private var spacing: SelahSpacing { SelahSpacing(rawValue: spacingRaw) ?? .comfortable }

    init(draft: SelahDraft, onSave: @escaping (SelahDraft) -> Void, onDelete: (() -> Void)? = nil) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onDelete = onDelete
        _liveAttributed = State(initialValue: SelahRichText.build(body: draft.body, spans: draft.spans, spacing: SelahSpacing(rawValue: UserDefaults.standard.string(forKey: "nuru.selah.lineSpacing") ?? "") ?? .comfortable))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            TextField("Untitled", text: $draft.title)
                .font(.fraunces(20, .medium)).foregroundStyle(Nuru.navy)
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.md)

            ZStack(alignment: .topLeading) {
                if controller.isEmpty {
                    Text("Pause here — write your first thought.")
                        .font(.inter(16, .regular)).foregroundStyle(Nuru.ink300)
                        .padding(.horizontal, Nuru.S.md + 10).padding(.top, Nuru.S.md + 14)
                        .allowsHitTesting(false)
                }
                RichTextEditor(controller: controller, initial: liveAttributed, placeholder: "Pause here — write your first thought.") { updated in
                    liveAttributed = updated
                }
            }
            .padding(.horizontal, Nuru.S.md)
            .frame(maxHeight: .infinity)

            if !draft.drawingUrls.isEmpty { drawingStrip }
            toolbar
            saveButton
        }
        .background(Nuru.paper.ignoresSafeArea())
        .sheet(isPresented: $showDrawing) {
            SelahDrawingSheet { url in draft.drawingUrls.append(url) }
        }
        .confirmationDialog("Delete this thought?", isPresented: $pendingDelete, titleVisibility: .visible) {
            Button("Delete thought", role: .destructive) { onDelete?(); dismiss() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It will be removed from Selah on every device.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Circle().fill(Nuru.surface).frame(width: 32, height: 32)
                    .overlay(Icon(.x, size: 14, color: Nuru.navy))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Spacer(minLength: 0)
            Text("SELAH").font(.inter(11, .bold)).tracking(1.8).foregroundStyle(Color(hex: 0x9A7A2A))
            Spacer(minLength: 0)
            if !draft.isNew {
                Button { Haptics.tap(); pendingDelete = true } label: {
                    Circle().fill(Nuru.surface).frame(width: 32, height: 32)
                        .overlay(Icon(.trash2, size: 14, color: Color(hex: 0xB91C1C)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete thought")
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.md)
    }

    // MARK: Drawing thumbnails

    private var drawingStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Nuru.S.sm) {
                ForEach(Array(draft.drawingUrls.enumerated()), id: \.offset) { idx, url in
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: URL(string: url)) { $0.resizable().scaledToFill() }
                            placeholder: { Nuru.surface }
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                        Button {
                            Haptics.tap(); draft.drawingUrls.remove(at: idx)
                        } label: {
                            Icon(.x, size: 10, color: .white)
                                .frame(width: 18, height: 18)
                                .background(Color.black.opacity(0.55), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                    }
                }
            }
            .padding(.horizontal, Nuru.S.screen)
        }
        .padding(.top, Nuru.S.sm)
    }

    // MARK: Toolbar (bold · italic · color · font · spacing · draw)

    private var toolbar: some View {
        HStack(spacing: Nuru.S.sm) {
            toolbarButton(system: "bold", active: controller.selectionBold) { controller.toggleBold() }
            toolbarButton(system: "italic", active: controller.selectionItalic) { controller.toggleItalic() }
            Menu {
                ForEach(SelahColor.allCases) { c in
                    Button {
                        Haptics.tap(); controller.applyColor(c)
                    } label: {
                        Label(colorLabel(c), systemImage: "circle.fill")
                    }
                }
            } label: {
                toolbarIcon(system: "paintpalette")
            }
            Menu {
                ForEach(SelahFont.allCases) { f in
                    Button(f.label) { Haptics.tap(); controller.applyFont(f) }
                }
            } label: {
                toolbarIcon(system: "textformat")
            }
            Menu {
                ForEach(SelahSpacing.allCases) { s in
                    Button(s.label) {
                        Haptics.tap(); spacingRaw = s.rawValue; controller.applySpacing(s)
                    }
                }
            } label: {
                toolbarIcon(system: "arrow.up.and.down.text.horizontal")
            }
            if isPenCapableDevice {
                Button { Haptics.tap(); showDrawing = true } label: {
                    toolbarIcon(system: "pencil.tip.crop.circle")
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.vertical, Nuru.S.sm)
        .background(Color.white)
        .overlay(alignment: .top) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    private func colorLabel(_ c: SelahColor) -> String {
        switch c {
        case .ink: return "Ink"
        case .gold: return "Gold"
        case .crimson: return "Crimson"
        case .forest: return "Forest"
        case .ocean: return "Ocean"
        case .plum: return "Plum"
        }
    }

    private func toolbarButton(system: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            toolbarIcon(system: system, active: active)
        }
        .buttonStyle(.plain)
    }

    private func toolbarIcon(system: String, active: Bool = false) -> some View {
        Image(systemName: system)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(active ? Color.white : Nuru.navy)
            .frame(width: 34, height: 34)
            .background(active ? Nuru.navy : Nuru.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Save

    private var bodyEmpty: Bool { liveAttributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var saveButton: some View {
        Button {
            Haptics.action()
            let (body, spans) = SelahRichText.extract(liveAttributed)
            draft.body = body
            draft.spans = spans
            onSave(draft)
            dismiss()
        } label: {
            Text(draft.isNew ? "Save thought" : "Save changes")
                .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: 0xC9A227), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(bodyEmpty)
        .opacity(bodyEmpty ? 0.5 : 1)
        .padding(Nuru.S.screen)
    }
}
