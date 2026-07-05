// Plan day reader — ONE elegant scroll for the whole day, replacing the old
// tab-through (a separate screen per segment). Every part of the day — Today's
// Reading, Devotional, Talk it Over, Prayer, Go Deeper — flows as a section on a
// single warm canvas: a navy day header with a live progress bar, a gold
// pull-quote for the scripture, serif teaching for the devotional, a reflection
// card for talk-it-over, a tinted prayer card, and a compact Go Deeper row. Each
// part ticks itself complete as you scroll past it (best-effort, non-blocking),
// so returning to the day view shows real per-part progress. Video segments keep
// an inline player card. Opened from a part row deep-links (scrolls) to that part.
import SwiftUI
import UIKit

struct PlanSegmentView: View {
    let ref: PlanSegmentRef
    init(ref: PlanSegmentRef) { self.ref = ref }

    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    @State private var viewedIds = Set<String>()
    @State private var player: VideoItem?

    private struct VideoItem: Identifiable { let id = UUID(); let url: URL }

    private var segments: [PlanSegment] { ref.segments }

    /// Fraction of the day's parts read (server-confirmed OR viewed this session).
    private var progress: Double {
        guard !segments.isEmpty else { return 0 }
        let done = segments.filter { $0.completed || viewedIds.contains($0.segmentId) }.count
        return Double(done) / Double(segments.count)
    }
    private var allDone: Bool {
        !segments.isEmpty && segments.allSatisfy { $0.completed || viewedIds.contains($0.segmentId) }
    }

    var body: some View {
        ZStack {
            Nuru.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Nuru.S.lg) {
                            ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                                section(seg)
                                    .id(seg.segmentId)
                                if idx < segments.count - 1 {
                                    Rectangle().fill(Nuru.gold.opacity(0.14))
                                        .frame(height: 1).frame(maxWidth: 64)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                            EncouragementRow()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Nuru.S.screen)
                        .padding(.top, Nuru.S.base)
                        .padding(.bottom, Nuru.S.xl)
                    }
                    .safeAreaInset(edge: .bottom) { bottomCTA }
                    .onAppear {
                        // Deep-link: a tapped part row scrolls that section into view.
                        guard ref.index > 0, ref.index < segments.count else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(segments[ref.index].segmentId, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $player) { item in immersivePlayer(item.url) }
        .onAppear { tabs.chromeHidden = true }
        .onDisappear { tabs.chromeHidden = false }   // leaf reader (Home shortcut) — restore the bar
    }

    // MARK: Navy day header (kicker · serif day title · progress bar)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    headerChip { Icon(.arrowLeft, size: 18, color: .white) }
                }
                .buttonStyle(.pressable)
                Spacer(minLength: Nuru.S.sm)
                Text("DAY \(ref.dayNumber)")
                    .font(.inter(10, .bold)).kerning(2.0)
                    .foregroundStyle(Nuru.gold)
                Spacer(minLength: Nuru.S.sm)
                headerChip { Icon(.bookmark, size: 16, color: Nuru.gold) }
            }
            Text(ref.planTitle)
                .font(.fraunces(22, .semibold))
                .foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.8)
                .padding(.top, Nuru.S.md)
            progressBar
                .padding(.top, Nuru.S.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.sm)
        .padding(.bottom, Nuru.S.md)
        .background(
            Nuru.navy
                .clipShape(.rect(bottomLeadingRadius: 20, bottomTrailingRadius: 20))
                .ignoresSafeArea(edges: .top)
        )
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(Nuru.gold)
                    .frame(width: max(6, geo.size.width * progress))
            }
        }
        .frame(height: 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: progress)
    }

    private func headerChip<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(width: 38, height: 38)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: One section per segment (overline + kind-aware body)

    @ViewBuilder
    private func section(_ seg: PlanSegment) -> some View {
        let done = seg.completed || viewedIds.contains(seg.segmentId)
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack(spacing: 6) {
                Text(overline(seg))
                    .font(.inter(11, .bold)).kerning(1.6)
                    .foregroundStyle(Nuru.goldLo)
                if let r = seg.reference, !r.isEmpty, seg.kind.lowercased() == "scripture" {
                    Text("· \(r)").font(.inter(11, .medium)).foregroundStyle(Nuru.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(done ? Nuru.gold : Nuru.muted.opacity(0.4))
            }
            body(seg)
        }
    }

    @ViewBuilder
    private func body(_ seg: PlanSegment) -> some View {
        switch seg.kind.lowercased() {
        case "video":
            videoCard(seg)
        case "scripture":
            PullQuoteCard(text: (seg.content?.isEmpty == false ? seg.content : nil) ?? seg.reference ?? seg.title,
                          caption: seg.reference ?? "Scripture",
                          quoted: seg.content?.isEmpty == false)
        case "talk":
            if let p = seg.content, !p.isEmpty { ReaderReflectionCard(prompt: p) }
            else if let r = seg.reference, !r.isEmpty { PullQuoteCard(text: r, caption: "Scripture", quoted: false) }
        case "reading":
            if let c = seg.content, !c.isEmpty { GoDeeperRow(refs: c) }
        default:
            // "Pray" is a devotional-kind segment but reads as a prayer.
            if seg.title.lowercased().hasPrefix("pray"), let c = seg.content, !c.isEmpty {
                PrayerCard(text: c)
            } else if let c = seg.content, !c.isEmpty {
                PassageText(content: c)
            }
        }
    }

    /// Section overline from the segment title (falls back to a kind label).
    private func overline(_ seg: PlanSegment) -> String {
        let t = seg.title
        if !t.isEmpty {
            if t.lowercased().hasPrefix("pray") { return "PRAYER" }
            return t.uppercased()
        }
        switch seg.kind.lowercased() {
        case "video": return "WATCH"
        case "reading": return "GO DEEPER"
        case "devotional": return "DEVOTIONAL"
        case "talk": return "TALK IT OVER"
        case "scripture": return "TODAY'S READING"
        default: return seg.kind.uppercased()
        }
    }

    // MARK: Inline video card (real videoUrl only)

    private func videoCard(_ seg: PlanSegment) -> some View {
        ZStack {
            mediaBackground(seg)
            Button {
                Haptics.tap()
                if let u = seg.videoUrl.flatMap(URL.init) { player = VideoItem(url: u) }
            } label: {
                ZStack {
                    Circle().fill(Nuru.gold).frame(width: 60, height: 60).nuruShadow()
                    Icon(.play, size: 20, color: Nuru.navy).offset(x: 1)
                }
            }
            .buttonStyle(.pressable)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .nuruShadow()
    }

    @ViewBuilder
    private func mediaBackground(_ seg: PlanSegment) -> some View {
        if let url = seg.imageUrl.flatMap(URL.init) {
            Color.clear
                .overlay {
                    CachedAsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                                .transition(.opacity.animation(.easeOut(duration: 0.25)))
                        } else {
                            Rectangle().fill(Nuru.navyGradient)
                        }
                    }
                }
                .clipped()
        } else {
            Rectangle().fill(Nuru.navyGradient)
        }
    }

    // MARK: Bottom CTA — finish the day's reading

    private var bottomCTA: some View {
        Button {
            // Ensure every part is recorded, then hand back to the day view
            // (where "Mark day complete" finalises the day per the per-part model).
            for seg in segments { markViewed(seg) }
            Haptics.success()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Icon(.check, size: 15, color: .white)
                Text(allDone ? "Done for today" : "Finish reading")
                    .font(.inter(14, .bold)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Nuru.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.md)
        .padding(.bottom, Nuru.S.md)
        .background(
            LinearGradient(colors: [Nuru.surface.opacity(0), Nuru.surface],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: Immersive video player (full-bleed)

    private func immersivePlayer(_ url: URL) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                HStack {
                    Button { player = nil } label: {
                        Icon(.x, size: 18, color: .white)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.pressable)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Nuru.S.screen).padding(.top, Nuru.S.sm)
                Spacer(minLength: 0)
                Button {
                    Haptics.action()
                    UIApplication.shared.open(url)
                } label: {
                    HStack(spacing: Nuru.S.sm) {
                        Icon(.play, size: 16, color: Nuru.navy)
                        Text("Start watching").font(.inter(16, .bold)).foregroundStyle(Nuru.navy)
                    }
                    .frame(maxWidth: .infinity).frame(height: Nuru.buttonHeightLg)
                    .background(Nuru.white, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.horizontal, Nuru.S.screen).padding(.bottom, Nuru.S.xl)
            }
        }
    }

    // MARK: Completion (per-part, best-effort, non-blocking)

    private func markViewed(_ seg: PlanSegment) {
        guard !viewedIds.contains(seg.segmentId), !seg.completed else {
            viewedIds.insert(seg.segmentId); return
        }
        viewedIds.insert(seg.segmentId)
        Task { _ = try? await MemberAPI.completePlanSegment(seg.segmentId) }
    }
}

// MARK: - Reader pieces

/// Serif passage copy split into paragraphs on blank lines, with a leading verse
/// number rendered as a small raised gold marker when a line opens with one.
private struct PassageText: View {
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            ForEach(Self.lines(content)) { line in paragraph(line) }
        }
    }
    private func paragraph(_ line: Line) -> some View {
        (numberText(line.number) + Text(line.text)
            .font(.fraunces(16, .regular))
            .foregroundStyle(Nuru.navy))
            .lineSpacing(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func numberText(_ n: String?) -> Text {
        guard let n else { return Text("") }
        return Text("\(n)  ").font(.inter(11, .bold)).foregroundStyle(Nuru.gold).baselineOffset(5)
    }
    struct Line: Identifiable { let id: Int; let number: String?; let text: String }
    static func lines(_ content: String) -> [Line] {
        content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { idx, raw in
                let digits = raw.prefix(while: \.isNumber)
                if (1...3).contains(digits.count) {
                    var rest = raw.dropFirst(digits.count)
                    if let f = rest.first, ".):".contains(f) { rest = rest.dropFirst() }
                    if rest.first == " " {
                        return Line(id: idx, number: String(digits), text: rest.trimmingCharacters(in: .whitespaces))
                    }
                }
                return Line(id: idx, number: nil, text: raw)
            }
    }
}

/// Gold pull-quote card. Never double-quotes: if the text already opens with a
/// quotation glyph (the verse text carries curly quotes from the source), it is
/// rendered as-is instead of being wrapped again.
private struct PullQuoteCard: View {
    let text: String
    let caption: String
    var quoted = true

    private var display: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let alreadyQuoted = t.hasPrefix("\u{201C}") || t.hasPrefix("\"")
        return (quoted && !alreadyQuoted) ? "\u{201C}\(t)\u{201D}" : t
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Nuru.gold).frame(width: 3)
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Icon(.quote, size: 16, color: Nuru.gold)
                Text(display)
                    .font(.fraunces(18, .regular))
                    .foregroundStyle(Nuru.navy)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption.uppercased())
                    .font(.nCardKicker).kerning(1.4)
                    .foregroundStyle(Nuru.muted)
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Talk-it-over prompt card — serif questions on a white card.
private struct ReaderReflectionCard: View {
    let prompt: String
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                ForEach(Self.questions(prompt), id: \.self) { q in
                    HStack(alignment: .top, spacing: 8) {
                        Icon(.messageCircle, size: 13, color: Nuru.goldLo).padding(.top, 3)
                        Text(q)
                            .font(.fraunces(15, .regular)).foregroundStyle(Nuru.navy)
                            .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
    /// The prompt stores questions as em-dash bullets separated by blank lines.
    static func questions(_ s: String) -> [String] {
        let parts = s.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("—") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
        return parts.isEmpty ? [s] : parts
    }
}

/// Prayer card — warm gold tint, serif prayer, an italic closing blessing.
private struct PrayerCard: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            if !prayer.isEmpty {
                Text(prayer)
                    .font(.fraunces(15, .regular)).foregroundStyle(Nuru.navy)
                    .lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            }
            if let b = blessing, !b.isEmpty {
                Text(b)
                    .font(.fraunces(14, .regular)).italic()
                    .foregroundStyle(Nuru.goldLo)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.gold.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.gold.opacity(0.22), lineWidth: 1))
    }
    // Split the prayer body from a trailing italic blessing (`_…_`).
    private var lines: [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var blessing: String? {
        guard let last = lines.last, last.hasPrefix("_"), last.hasSuffix("_"), last.count > 2 else { return nil }
        return String(last.dropFirst().dropLast())
    }
    private var prayer: String {
        let body = blessing == nil ? lines : Array(lines.dropLast())
        return body.joined(separator: "\n\n")
    }
}

/// Compact Go Deeper row — the extra references on a soft surface, no dead space.
private struct GoDeeperRow: View {
    let refs: String
    var body: some View {
        HStack(alignment: .center, spacing: Nuru.S.sm) {
            Icon(.bookOpen, size: 15, color: Nuru.goldLo)
            Text(refs)
                .font(.fraunces(14, .regular)).foregroundStyle(Nuru.navy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.gold.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The reader's gentle sign-off line on a soft gold tint.
private struct EncouragementRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.sm) {
            Icon(.handHeart, size: 16, color: Nuru.gold)
            Text("Every faithful day adds up. There's no rush — just presence.")
                .font(.nCardBody)
                .foregroundStyle(Nuru.navy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Nuru.S.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
