// Focused part reader — page 4 of the plan journey (Plan → Days → Day hub →
// THIS). One part of the day at a time (Watch / Listen / Scripture / Devotional /
// Talk it Over / Prayer / Go Deeper) on a warm reading canvas. "Finished" ticks
// the part (server-backed), posts .nuruPlanPartDone so the day hub's row ticks
// the moment the member returns, and pops back — read, tick, back, pick the next.
// The Prayer part carries the day's reflection box at the bottom. Video/audio
// open in a window over the content. Honors the warm night/sepia reader mode.
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted (object = segmentId) when a part is finished in its reader.
    static let nuruPlanPartDone = Notification.Name("nuruPlanPartDone")
}

struct PlanSegmentView: View {
    let ref: PlanSegmentRef
    init(ref: PlanSegmentRef) { self.ref = ref }

    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("readerNight") private var readerNight = false
    @State private var done = false
    @State private var saving = false
    @State private var player: MediaItem?

    private struct MediaItem: Identifiable { let id = UUID(); let url: URL }

    private var pal: ReaderPalette { ReaderPalette(night: readerNight) }
    private var segment: PlanSegment { ref.segments[min(max(ref.index, 0), ref.segments.count - 1)] }
    private var isPray: Bool { segment.title.lowercased().hasPrefix("pray") }

    var body: some View {
        ZStack {
            pal.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                        if isPray, let pid = ref.planId {
                            PartReflectionBox(planId: pid, dayNumber: ref.dayNumber)
                        }
                        DayEncouragement()
                    }
                    .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) { cta }
            }
        }
        .environment(\.readerPalette, pal)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $player) { it in mediaWindow(it.url) }
        .onAppear { tabs.chromeHidden = true; if segment.completed { done = true } }
    }

    // MARK: header — back · medallion + part name · DAY N kicker · night toggle

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: .white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                Spacer(minLength: 8)
                Text("DAY \(ref.dayNumber) · \(ref.planTitle.uppercased())")
                    .font(.inter(10, .bold)).kerning(1.6).foregroundStyle(PL.gold)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.25)) { readerNight.toggle() }
                } label: {
                    Icon(readerNight ? .sun : .moon, size: 17, color: .white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(readerNight ? "Day mode" : "Night mode")
            }
            HStack(spacing: 12) {
                Icon(partIcon, size: 16, color: PL.gold)
                    .frame(width: 40, height: 40)
                    .background(PL.gold.opacity(0.16), in: Circle())
                    .overlay(Circle().stroke(PL.gold.opacity(0.4), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(partName).font(.fraunces(24, .semibold)).foregroundStyle(.white)
                    if let r = segment.reference, !r.isEmpty {
                        Text(r).font(.inter(11)).foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        .background(
            LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(.rect(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
                .ignoresSafeArea(edges: .top)
        )
    }

    private var partName: String {
        if isPray { return "Prayer" }
        switch segment.kind.lowercased() {
        case "video": return "Watch"
        case "audio": return "Listen"
        case "scripture": return "Scripture"
        case "talk": return "Talk it Over"
        case "reading": return "Go Deeper"
        default: return "Devotional"
        }
    }

    private var partIcon: Lucide {
        if isPray { return .handHeart }
        switch segment.kind.lowercased() {
        case "video", "audio": return .play
        case "scripture": return .quote
        case "talk": return .messageCircle
        case "reading": return .bookOpen
        default: return .sun
        }
    }

    // MARK: content per part (shared Day* reading components)

    @ViewBuilder private var content: some View {
        switch segment.kind.lowercased() {
        case "video", "audio":
            DayVideoCard(seg: segment) { url in player = MediaItem(url: url) }
            if let c = segment.content, !c.isEmpty { DayPassage(content: c) }
        case "scripture":
            DayPullQuote(text: (segment.content?.isEmpty == false ? segment.content! : (segment.reference ?? segment.title)),
                         caption: segment.reference ?? "Scripture",
                         quoted: segment.content?.isEmpty == false)
        case "talk":
            if let c = segment.content, !c.isEmpty { DayTalk(prompt: c) }
        case "reading":
            if let c = segment.content, !c.isEmpty { DayGoDeeper(refs: c) }
        default:
            if isPray, let c = segment.content, !c.isEmpty { DayPrayer(text: c) }
            else if let c = segment.content, !c.isEmpty { DayPassage(content: c) }
        }
    }

    // MARK: finish — tick + notify the hub + return

    private var cta: some View {
        Button {
            guard !saving else { return }
            if done {
                Haptics.tap(); dismiss(); return
            }
            saving = true
            Task {
                _ = try? await MemberAPI.completePlanSegment(segment.segmentId)
                NotificationCenter.default.post(name: .nuruPlanPartDone, object: segment.segmentId)
                done = true; saving = false
                Haptics.success()
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if saving { ProgressView().tint(PL.navy) }
                else { Icon(.check, size: 15, color: PL.navy) }
                Text(done ? "Done" : "Finished — mark as read")
                    .font(.inter(14, .bold)).foregroundStyle(PL.navy)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: PL.gold.opacity(0.4), radius: 10, y: 6)
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
        .background(
            LinearGradient(colors: [pal.bg.opacity(0), pal.bg], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: media window (over the content)

    private func mediaWindow(_ url: URL) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                HStack {
                    Button { player = nil } label: {
                        Icon(.x, size: 18, color: .white)
                            .frame(width: 38, height: 38).background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.pressable)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.top, 12)
                Spacer(minLength: 0)
                Button { openURL(url) } label: {
                    HStack(spacing: 8) {
                        Icon(.play, size: 16, color: PL.navy)
                        Text("Start playing").font(.inter(16, .bold)).foregroundStyle(PL.navy)
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Reflection box (lives at the bottom of the Prayer part)

/// The day's reflection, saved to the plan-day reflection endpoint (upsert).
/// Pre-fills on return visits; the button flips to "Update".
private struct PartReflectionBox: View {
    let planId: String
    let dayNumber: Int

    @Environment(\.readerPalette) private var pal
    @State private var text = ""
    @State private var saved: PlanDayReflection?
    @State private var saving = false
    @State private var justSaved = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("REFLECTION").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
                Spacer(minLength: 0)
                if justSaved {
                    HStack(spacing: 4) {
                        Icon(.check, size: 11, color: Color(hex: 0x16A34A))
                        Text("Saved").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x15803D))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            Text("What is God showing you today?")
                .font(.fraunces(16, .medium)).italic().foregroundStyle(pal.ink)
                .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Write it down while it's fresh…").font(.inter(13)).foregroundStyle(pal.inkDim)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                }
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(4...10)
                    .font(.inter(13)).foregroundStyle(pal.ink).tint(pal.gold)
                    .focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { focused = false }
                                .font(.inter(14, .semibold)).foregroundStyle(pal.goldDeep)
                        }
                    }
            }
            .background(pal.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(pal.border, lineWidth: 1))
            Button {
                Haptics.action()
                Task { await save() }
            } label: {
                HStack(spacing: 6) {
                    if saving { ProgressView().tint(pal.goldDeep) }
                    else { Icon(.pencil, size: 13, color: pal.goldDeep) }
                    Text(saved == nil ? "Save reflection" : "Update")
                        .font(.inter(12, .bold)).foregroundStyle(pal.goldDeep)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(pal.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(pal.gold.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(16)
        .background(pal.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(pal.border, lineWidth: 1))
        .task {
            guard let row = try? await MemberAPI.planDayReflection(planId: planId, dayNumber: dayNumber) else { return }
            saved = row
            if text.isEmpty { text = row.body }
        }
    }

    private func save() async {
        let body = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !body.isEmpty, !saving else { return }
        saving = true
        if let row = try? await MemberAPI.savePlanDayReflection(planId: planId, dayNumber: dayNumber, body: body) {
            saved = row
            Haptics.success()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { justSaved = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.easeOut(duration: 0.25)) { justSaved = false }
            }
        } else {
            Haptics.error()
        }
        saving = false
    }
}
