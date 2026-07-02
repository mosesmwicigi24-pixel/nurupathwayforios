// Plan segment — the native port of screens/PlanSegmentScreen.tsx, presented as
// the Figma make's ReadingDayReader: a navy day header (gold kicker, serif title,
// per-segment step chips), a warm reader canvas with serif passage text (small
// gold verse numbers when the content carries them), a gold pull-quote card for
// the featured scripture, a REFLECTION prompt card for talk-it-over segments,
// an encouragement line, and a pinned completion CTA. Real segment data
// throughout — the Figma's mock audio/video timers are skipped because the
// model carries no media beyond `videoUrl`; video segments keep the immersive
// full-bleed player.
import SwiftUI
import UIKit

struct PlanSegmentView: View {
    let ref: PlanSegmentRef
    init(ref: PlanSegmentRef) { self.ref = ref }

    @Environment(\.dismiss) private var dismiss
    @State private var showPlayer = false
    @State private var completed = false

    private var segment: PlanSegment { ref.segments[ref.index] }
    private var isVideo: Bool {
        segment.kind.lowercased() == "video" && (segment.videoUrl?.isEmpty == false)
    }
    private var hasNext: Bool { ref.index + 1 < ref.segments.count }

    /// Gold overline label per segment kind (WATCH / READ / DEVOTIONAL / …) —
    /// used by the immersive player.
    private var overline: String {
        switch segment.kind.lowercased() {
        case "video":      return "WATCH"
        case "reading":    return "READ"
        case "devotional": return "DEVOTIONAL"
        case "talk":       return "TALK IT OVER"
        case "scripture":  return "SCRIPTURE"
        default:           return segment.kind.uppercased()
        }
    }

    /// Short label per segment kind for the header step chips.
    private static func chipLabel(_ kind: String) -> String {
        switch kind.lowercased() {
        case "video":      return "Watch"
        case "reading":    return "Read"
        case "devotional": return "Devotional"
        case "talk":       return "Talk"
        case "scripture":  return "Scripture"
        default:           return kind.capitalized
        }
    }

    /// Header caption: the scripture reference, else the segment kind.
    private var headerCaption: String {
        if let r = segment.reference, !r.isEmpty { return r }
        return Self.chipLabel(segment.kind)
    }

    var body: some View {
        ZStack {
            Nuru.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Nuru.S.base) {
                        if isVideo { videoCard }
                        readerBlocks
                        EncouragementRow()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.S.xl)
                }
                .safeAreaInset(edge: .bottom) { bottomCTA }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showPlayer) { immersivePlayer }
        .task {
            // Read-type segments count as viewed on open (non-blocking, best-effort).
            if !isVideo { await markComplete() }
        }
    }

    // MARK: Navy day header (kicker · serif title · step chips)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    headerChip { Icon(.arrowLeft, size: 18, color: .white) }
                }
                .buttonStyle(.pressable)
                Spacer(minLength: Nuru.S.sm)
                Text("DAY \(ref.dayNumber) · \(ref.planTitle.uppercased())")
                    .font(.inter(10, .bold)).kerning(1.8)
                    .foregroundStyle(Nuru.gold)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: Nuru.S.sm)
                headerChip { Icon(.bookmark, size: 16, color: Nuru.gold) }
            }
            Text(segment.title)
                .font(.fraunces(22, .semibold))
                .foregroundStyle(.white)
                .padding(.top, Nuru.S.md)
            Text(headerCaption)
                .font(.inter(12, .regular))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 2)
            stepChips
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

    private func headerChip<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(width: 38, height: 38)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// One chip per sibling segment of the day — gold once completed.
    private var stepChips: some View {
        HStack(spacing: 6) {
            ForEach(Array(ref.segments.enumerated()), id: \.element.id) { idx, seg in
                StepChip(label: Self.chipLabel(seg.kind),
                         done: seg.completed || (idx == ref.index && completed))
            }
        }
        // The current chip turning gold settles in rather than snapping.
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: completed)
    }

    // MARK: 16:9 video card (real `videoUrl` only)

    private var videoCard: some View {
        ZStack {
            mediaBackground
            Button { Haptics.tap(); showPlayer = true } label: {
                ZStack {
                    Circle().fill(Nuru.gold).frame(width: 64, height: 64).nuruShadow()
                    Icon(.play, size: 22, color: Nuru.navy)
                        .offset(x: 1) // optically centre the play triangle
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
    private var mediaBackground: some View {
        if let url = segment.imageUrl.flatMap(URL.init) {
            CachedAsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                        .transition(.opacity.animation(.easeOut(duration: 0.25))) // no pop
                } else {
                    Rectangle().fill(Nuru.navyGradient)
                }
            }
        } else {
            Rectangle().fill(Nuru.navyGradient)
        }
    }

    // MARK: Reader blocks per segment kind

    @ViewBuilder
    private var readerBlocks: some View {
        switch segment.kind.lowercased() {
        case "scripture":
            // Scripture segments ARE the featured verse — the whole content goes
            // in the pull-quote card.
            PullQuoteCard(text: (segment.content?.isEmpty == false ? segment.content : nil)
                                ?? segment.reference ?? segment.title,
                          caption: segment.reference ?? "Scripture",
                          quoted: segment.content?.isEmpty == false)
        case "talk":
            if let prompt = segment.content, !prompt.isEmpty {
                ReaderReflectionCard(prompt: prompt)
            } else if let r = segment.reference, !r.isEmpty {
                PullQuoteCard(text: r, caption: "Scripture", quoted: false)
            }
        default:
            if let content = segment.content, !content.isEmpty {
                PassageText(content: content)
            }
            if let r = segment.reference, !r.isEmpty, r != segment.content {
                PullQuoteCard(text: r, caption: "Scripture", quoted: false)
            }
        }
    }

    // MARK: Pinned completion CTA (gradient fade + navy button)

    private var bottomCTA: some View {
        VStack(spacing: 0) {
            if hasNext {
                NavigationLink(value: nextRef) { ctaLabel("Continue") }
                    .buttonStyle(.pressable)
                    .simultaneousGesture(TapGesture().onEnded {
                        Haptics.tap()
                        Task { await markComplete() }
                    })
            } else {
                Button {
                    let alreadyDone = completed || segment.completed
                    Task {
                        await markComplete()
                        // Celebrate only the first completion, not a revisit.
                        if alreadyDone { Haptics.tap() } else { Haptics.success() }
                        dismiss()
                    }
                } label: {
                    ctaLabel(completed || segment.completed ? "Done" : "Mark complete")
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.md)
        .padding(.bottom, Nuru.S.md)
        .background(
            LinearGradient(colors: [Nuru.surface.opacity(0), Nuru.surface],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func ctaLabel(_ title: String) -> some View {
        Text(title)
            .font(.inter(14, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Nuru.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var nextRef: PlanSegmentRef {
        PlanSegmentRef(planTitle: ref.planTitle,
                       dayNumber: ref.dayNumber,
                       segments: ref.segments,
                       index: ref.index + 1)
    }

    // MARK: Immersive player (full-bleed cover)

    private var immersivePlayer: some View {
        ZStack {
            // Full-bleed background image + dark scrim.
            mediaBackground
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
            LinearGradient(
                colors: [Color.black.opacity(0.15), Color.black.opacity(0.55), Color.black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { showPlayer = false } label: {
                        Icon(.x, size: 18, color: .white)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.pressable)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.sm)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: Nuru.S.sm) {
                    Text(overline)
                        .font(.inter(11, .semibold)).kerning(1.5)
                        .foregroundStyle(Nuru.gold)
                    Text(segment.title)
                        .font(.fraunces(30, .semibold))
                        .foregroundStyle(.white)
                    if let sub = segment.reference ?? segment.content, !sub.isEmpty {
                        Text(sub)
                            .font(.nBodyLg)
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Nuru.S.screen)

                startWatchingButton
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.lg)
                    .padding(.bottom, Nuru.S.xl)
            }
        }
    }

    @ViewBuilder
    private var startWatchingButton: some View {
        if let url = segment.videoUrl.flatMap(URL.init) {
            Button {
                Haptics.action()
                UIApplication.shared.open(url)
                Task { await markComplete() }
            } label: {
                HStack(spacing: Nuru.S.sm) {
                    Icon(.play, size: 16, color: Nuru.navy)
                    Text("Start Watching")
                        .font(.inter(16, .bold))
                        .foregroundStyle(Nuru.navy)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Nuru.buttonHeightLg)
                .background(Nuru.white, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
    }

    // MARK: Completion (best-effort, non-blocking)

    private func markComplete() async {
        guard !completed, !segment.completed else { completed = true; return }
        _ = try? await MemberAPI.completePlanSegment(segment.segmentId)
        completed = true
    }
}

// MARK: - Reader pieces (small private structs keep the body's type metadata light)

/// One header step chip — gold with a check once its segment is done.
private struct StepChip: View {
    let label: String
    let done: Bool
    var body: some View {
        HStack(spacing: 3) {
            if done { Icon(.check, size: 9, color: Nuru.navy) }
            Text(label)
                .font(.inter(10, .bold))
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .foregroundStyle(done ? Nuru.navy : Color.white.opacity(0.7))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(done ? Nuru.gold : Color.white.opacity(0.08), in: Capsule())
    }
}

/// Serif passage copy. Lines that open with a verse number ("14 but whoever…")
/// render it as a small raised gold marker, matching the Figma reader.
private struct PassageText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            ForEach(Self.lines(content)) { line in
                paragraph(line)
            }
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
        return Text("\(n)  ")
            .font(.inter(11, .bold))
            .foregroundStyle(Nuru.gold)
            .baselineOffset(5)
    }

    struct Line: Identifiable {
        let id: Int
        let number: String?
        let text: String
    }

    /// Split into trimmed non-empty lines; peel a leading verse number ("14 ",
    /// "14. ", "14) ", "14: ") when present.
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
                        return Line(id: idx, number: String(digits),
                                    text: rest.trimmingCharacters(in: .whitespaces))
                    }
                }
                return Line(id: idx, number: nil, text: raw)
            }
    }
}

/// Gold pull-quote card — verse tint (#FFF8E6), gold spine + hairline, Quote
/// glyph, serif text, uppercase reference caption.
private struct PullQuoteCard: View {
    let text: String
    let caption: String
    var quoted = true

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Nuru.gold).frame(width: 3)
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Icon(.quote, size: 16, color: Nuru.gold)
                Text(quoted ? "\u{201C}\(text)\u{201D}" : text)
                    .font(.fraunces(18, .regular))
                    .foregroundStyle(Nuru.navy)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption.uppercased())
                    .font(.inter(11, .semibold)).kerning(1.6)
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

/// "REFLECTION" prompt card — serif prompt on a white card (talk-it-over segments).
private struct ReaderReflectionCard: View {
    let prompt: String
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text("REFLECTION")
                    .font(.inter(10, .bold)).tracking(1.8)
                    .foregroundStyle(Nuru.goldLo)
                Text(prompt)
                    .font(.fraunces(15, .regular))
                    .foregroundStyle(Nuru.navy)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The reader's gentle sign-off line on a soft gold tint.
private struct EncouragementRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.sm) {
            Icon(.handHeart, size: 16, color: Nuru.gold)
            Text("Every faithful day adds up. There's no rush — just presence.")
                .font(.inter(12, .regular))
                .foregroundStyle(Nuru.navy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Nuru.S.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
