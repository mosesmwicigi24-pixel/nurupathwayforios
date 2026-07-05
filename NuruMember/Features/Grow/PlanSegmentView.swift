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

    /// The segments this page renders — a combined group ("word" = Scripture +
    /// teaching + Go Deeper; "respond" = Talk + Prayer) or the single segment.
    private var group: [PlanSegment] {
        switch ref.part {
        case "word": return ref.segments.filter { [1, 2, 5].contains(rank($0)) }
        case "respond": return ref.segments.filter { [3, 4].contains(rank($0)) }
        default: return [segment]
        }
    }
    private func rank(_ s: PlanSegment) -> Int {
        switch s.kind.lowercased() {
        case "video", "audio": return 0
        case "scripture": return 1
        case "talk": return 3
        case "reading": return 5
        default: return s.title.lowercased().hasPrefix("pray") ? 4 : 2
        }
    }

    var body: some View {
        ZStack {
            pal.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                        if ref.part == "respond", let pid = ref.planId {
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
        .onAppear { tabs.chromeHidden = true; if group.allSatisfy(\.completed) { done = true } }
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
                    Text(partName).font(.fraunces(24, .medium)).kerning(-0.7).foregroundStyle(.white)
                    if let r = headerRef, !r.isEmpty {
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
        switch ref.part {
        case "word": return "The Word"
        case "respond": return "Respond"
        default: return segment.kind.lowercased() == "audio" ? "Listen" : "Watch"
        }
    }

    private var partIcon: Lucide {
        switch ref.part {
        case "word": return .bookOpen
        case "respond": return .handHeart
        default: return .play
        }
    }

    /// Header caption — the scripture reference for The Word page.
    private var headerRef: String? {
        if ref.part == "word" {
            return group.first(where: { $0.kind.lowercased() == "scripture" })?.reference
        }
        return segment.reference
    }

    // MARK: content per part (shared Day* reading components)

    @ViewBuilder private var content: some View {
        switch ref.part {
        case "word":
            // Scripture woven straight into the teaching — one encouraging read,
            // Go Deeper folded in at the end.
            ForEach(group) { seg in
                switch seg.kind.lowercased() {
                case "scripture":
                    DayPullQuote(text: (seg.content?.isEmpty == false ? seg.content! : (seg.reference ?? seg.title)),
                                 caption: seg.reference ?? "Scripture",
                                 quoted: seg.content?.isEmpty == false)
                case "reading":
                    if let c = seg.content, !c.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GO DEEPER").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
                            DayGoDeeper(refs: c)
                        }
                    }
                default:
                    if let c = seg.content, !c.isEmpty { DayPassage(content: c) }
                }
            }
        case "respond":
            // Talk it Over → Prayer → your reflection, one response page.
            ForEach(group) { seg in
                if seg.kind.lowercased() == "talk", let c = seg.content, !c.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TALK IT OVER").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
                        DayTalk(prompt: c)
                    }
                } else if let c = seg.content, !c.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRAYER").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
                        DayPrayer(text: c)
                    }
                }
            }
        default:
            // Media page: a portrait, screen-filling player, then the title and
            // a few scanty keynotes just below.
            DayVideoCard(seg: segment, portrait: true) { url in player = MediaItem(url: url) }
            if !segment.title.isEmpty {
                Text(segment.title).font(.fraunces(20, .medium)).kerning(-0.4).foregroundStyle(pal.ink)
            }
            if let c = segment.content, !c.isEmpty { keynotes(c) }
        }
    }

    /// A few short keynote bullets (capped — scanty by design).
    private func keynotes(_ content: String) -> some View {
        let points = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(4)
        return VStack(alignment: .leading, spacing: 10) {
            Text("KEY POINTS").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(pal.gold).frame(width: 5, height: 5).padding(.top, 7)
                    Text(p).font(.inter(14, .medium)).foregroundStyle(pal.ink).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
                for seg in group where !seg.completed {
                    _ = try? await MemberAPI.completePlanSegment(seg.segmentId)
                    NotificationCenter.default.post(name: .nuruPlanPartDone, object: seg.segmentId)
                }
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
                .font(.fraunces(16.5, .regular)).italic().foregroundStyle(pal.ink)
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
