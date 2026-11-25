// The Sunday Letter, editorial (owner, 2026-10-07: board A, "the editorial
// letter") — a v3 letter (pathway#512) laid out like a designed page: the
// masthead and its dateline, the week's photograph, the title, a drop cap,
// the one shareable line as a pull quote, the week's true figures, the verse
// in full, the one step, the pastor's signature in his hand, and the letter
// kept as a one-page PDF.
//
// Every v3 field is optional on the wire; each section below shows only when
// its words came. A v2 letter never reaches this view (LetterView keeps it
// exactly as it was).
//
// Read aloud and the night page (member suggestion, 2026-11-21): listen and
// moon/sun circles in the page's top-left corner, close in its top-right, the
// player floating at the page's foot, and the page's ink is LetterInk — board
// A's own on the day page, the readers' sepia on the night page
// (ReadingTheme.swift). The whole page is drawn in this one view, so a flip
// redraws all of it.
import QuickLook
import SwiftUI
import UIKit

// MARK: - The words (pure — SundayLetterTests pins them)

enum LetterEditorialWords {
    /// "No. 6 · Sunday 4 October 2026" — the member's issue, then the Sunday
    /// the letter was written for (`week_of`, a date-only value: read in UTC).
    static func dateline(issueNo: Int?, weekOf: String) -> String {
        let day = sunday(weekOf).map { NuruDates.dateline($0, timeZone: utc) }
        return [issueNo.map { "No. \($0)" }, day].compactMap { $0 }.joined(separator: " · ")
    }

    /// `week_of` is a calendar date ("2026-10-04"): read and shown in UTC, so
    /// no time zone ever moves it to the Saturday.
    private static let utc = TimeZone(identifier: "UTC") ?? .current

    /// The letter's Sunday, or nil when `week_of` isn't a date.
    static func sunday(_ weekOf: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        let day = String(weekOf.trimmingCharacters(in: .whitespaces).prefix(10))
        return day.count == 10 ? f.date(from: day) : nil
    }

    /// "Your week, read back to you · 2 min".
    static func dek(readingMinutes: Int?) -> String {
        guard let m = readingMinutes, m > 0 else { return "Your week, read back to you" }
        return "Your week, read back to you · \(m) min"
    }

    /// The letter's paragraphs: v3's, else the body split on its blank lines.
    static func paragraphs(_ letter: PastoralLetter) -> [String] {
        if let p = letter.paragraphs, !p.isEmpty { return p }
        return letter.body.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The week's verse: v3's in full, else v2's bare reference, else none.
    static func scripture(_ letter: PastoralLetter) -> LetterScripture? {
        if let s = letter.scripture { return s }
        return letter.scriptureRef.map { LetterScripture(ref: $0, text: nil, version: nil) }
    }

    /// "Philippians 1:6 · WEB", or the reference alone.
    static func scriptureKicker(_ s: LetterScripture) -> String {
        [s.ref, s.version].compactMap { $0 }.joined(separator: " · ")
    }

    /// "YOUR WEEK, IN GRACE" shows when the week has a figure or a highlight.
    static func showsWeek(_ letter: PastoralLetter) -> Bool {
        !letter.figures.isEmpty || !letter.highlights.isEmpty
    }

    /// Who signs: v3's signer, else the church.
    static func signer(_ letter: PastoralLetter) -> LetterSigner {
        letter.signedBy ?? LetterSigner(name: "Nuru Place", role: nil)
    }

    /// The step's verb on its pill: a lesson begins, the journey continues.
    static func verb(_ step: LetterNextStep) -> String {
        step.route == "module" ? "Begin" : "Continue"
    }

    /// The pull quote: the line in the letter's own curly quotes.
    static func pullQuote(_ line: String) -> String {
        let opens = ["\u{201C}", "\""].contains { line.hasPrefix($0) }
        return opens ? line : "\u{201C}\(line)\u{201D}"
    }

    /// The member's letter before this one: the newest with an earlier Sunday.
    static func previous(_ letter: PastoralLetter, in letters: [PastoralLetter]) -> PastoralLetter? {
        func week(_ l: PastoralLetter) -> String { String(l.weekOf.trimmingCharacters(in: .whitespaces).prefix(10)) }
        let current = week(letter)
        guard !current.isEmpty else { return nil }
        return letters.filter { $0.letterId != letter.letterId && !week($0).isEmpty && week($0) < current }
            .max { week($0) < week($1) }
    }

    /// "Last week: Two prayers, answered" — and its own Sunday when it wasn't
    /// last week ("Sun 20 Sep: …", the year only when it isn't this letter's):
    /// never "last week" over an older letter. Android's previousLabel.
    static func previousLabel(_ previous: PastoralLetter, current: PastoralLetter) -> String {
        let title = previous.title
        guard let prev = sunday(previous.weekOf) else { return "Earlier: \(title)" }
        let cur = sunday(current.weekOf)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        if let cur, cal.date(byAdding: .day, value: 7, to: prev) == cur { return "Last week: \(title)" }
        return "\(NuruDates.day(prev, now: cur ?? prev, timeZone: utc)): \(title)"
    }

    /// The "Last week" row: its words and the one letter it opens — that
    /// letter itself, whose own row goes on further back. Nil for the
    /// member's first letter.
    static func lastWeek(_ letter: PastoralLetter, in letters: [PastoralLetter]) -> (label: String, opens: PastoralLetter)? {
        guard let earlier = previous(letter, in: letters) else { return nil }
        return (previousLabel(earlier, current: letter), earlier)
    }

    /// The row opens the member's own pastoral thread, which goes to their
    /// ASSIGNED pastor — who may not be the one who signed — so it says where
    /// the reply really goes (owner, 2026-10-07). The signature keeps the name.
    static let writeBackLabel = "Write back to your pastor"

    /// Why "Write back" didn't open, in the Pastor tab's own words (ChatView):
    /// no pastor yet is a 404, messages switched off a 403; anything else in
    /// §4's words.
    static func writeBackFailure(_ error: Error) -> String {
        if case .http(404, _, _, _)? = error as? APIError {
            return "No pastor is available for your congregation yet — please check back soon."
        }
        if case .http(403, _, _, _)? = error as? APIError {
            return "Direct messages aren't available on this account."
        }
        return NuruStateCopy.failureLine("Couldn't open your conversation with your pastor.", error)
    }

    /// The kept file's name: "Sunday Letter — Sunday 4 October 2026.pdf".
    static func pdfFileName(_ letter: PastoralLetter) -> String {
        let day = dateline(issueNo: nil, weekOf: letter.weekOf)
        return day.isEmpty ? "Sunday Letter.pdf" : "Sunday Letter — \(day).pdf"
    }

    /// The opening picture: the week's photograph, or the bundled art when
    /// there is none (its words come with it, or not at all).
    enum Hero: Equatable {
        case photo(URL, alt: String?, caption: String?)
        case art(imageKey: String)
    }

    static func hero(_ letter: PastoralLetter) -> Hero {
        if let p = letter.photo, let url = URL(string: p.url), let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            return .photo(url, alt: p.alt, caption: p.caption)
        }
        return .art(imageKey: letter.imageKey)
    }
}

/// The first paragraph's drop cap (board A): its initial, set in gold
/// display type two lines deep, the paragraph flowing around it.
enum LetterDropCap {
    /// How many of the reading lines the initial spans — board A's 58 pt
    /// cap beside 17/28 text.
    static let lines = 2
    static let gap: CGFloat = 8

    /// The initial and the rest. A paragraph that opens on anything but a
    /// letter (a quote mark, a figure — "10 lessons") keeps its first word
    /// whole: no drop cap.
    static func split(_ paragraph: String) -> (initial: String, rest: String)? {
        let p = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = p.first, first.isLetter, p.count > 1 else { return nil }
        return (String(first), String(p.dropFirst()))
    }
}

// MARK: - The page's ink

/// The letter's colours: board A's on the day page (exactly as it was), and
/// the readers' dark sepia on the night page (ReaderPalette's; Android's
/// EditorialLetter getters). `navy` is only ever words here, so on the night
/// page it is the light ink.
struct LetterInk: Equatable {
    var night: Bool = false

    static let dayBody = Color(hex: 0x1B2430)
    static let nightBody = Color(hex: 0xEBE3D3)
    static let dayGold = Color(hex: 0xA87F2E)
    static let nightGold = Color(hex: 0xD9B65A)

    var paper: Color { night ? Color(hex: 0x171411) : Color(hex: 0xFBF6EC) }
    var navy: Color { night ? Color(hex: 0xEBE3D3) : Color(hex: 0x0B1F33) }
    var body: Color { night ? Self.nightBody : Self.dayBody }
    var gold: Color { night ? Self.nightGold : Self.dayGold }
    var rule: Color { night ? Color(hex: 0xD9B65A) : Color(hex: 0xC89B3C) }
    var muted: Color { night ? Color(hex: 0x9A9280) : Color(hex: 0x5B6678) }
    var hairline: Color { night ? Color.white.opacity(0.09) : Color(hex: 0x0B1F33).opacity(0.10) }
    var verse: Color { night ? Color(hex: 0x251E13) : Color(hex: 0xFFF4DA) }
    /// The white cards and circles on the page.
    var card: Color { night ? Color(hex: 0x221E19) : Color.white }
    var chevron: Color { night ? Color(hex: 0x6B6455) : Color(hex: 0xB5BDC9) }
    var danger: Color { night ? Color(hex: 0xF87171) : Nuru.danger }

    var listenColors: ListenColors {
        ListenColors(bar: card, ink: navy, inkDim: muted, accent: Color(hex: 0xC89B3C),
                     onAccent: Color(hex: 0x0B1F33), border: hairline)
    }
}

// MARK: - The page

struct LetterEditorialView: View {
    let letter: PastoralLetter
    var onRead: () -> Void = {}
    /// The member's letters, when the caller already has them (the archive).
    var archive: [PastoralLetter] = []
    /// Inside the archive: "Last week" turns to that letter in place. From
    /// Home (nil), it opens the archive on that letter.
    var openEarlier: ((PastoralLetter) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The member's letters, for "Last week".
    @State private var letters: [PastoralLetter] = []
    /// The earlier letter opened from Home — shown in the archive, on it.
    @State private var earlierOpened: PastoralLetter?
    @State private var pdfFile: URL?
    @State private var fetchingPDF = false
    @State private var openingThread = false
    /// What a footer row couldn't do, in §4's words.
    @State private var actionLine: String?
    @State private var photoFailed = false

    // The reading theme: the member's choice, and the phone's own style for
    // Automatic — either changing redraws the page.
    @AppStorage(ReadingTheme.storageKey) private var readingTheme = ReadingTheme.auto.rawValue
    @ObservedObject private var appearance = ReadingAppearance.shared
    /// Read aloud (ReaderListen.letter): title, salutation, letter, verse, signature.
    @State private var listen = ListenReading.empty

    private var night: Bool { ReadingTheme.from(readingTheme).isNight(systemDark: appearance.systemDark) }
    /// Board A's ink — this is paper, whatever the phone's appearance — or
    /// the night page's, when the member reads by it.
    private var ink: LetterInk { LetterInk(night: night) }

    /// The reading text's leading: Fraunces 18 on 28-ish lines (board A's 17/28).
    private static let bodySpacing: CGFloat = 7

    private var paragraphs: [String] { LetterEditorialWords.paragraphs(letter) }
    private var signer: LetterSigner { LetterEditorialWords.signer(letter) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ink.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    masthead
                    hero
                    page
                }
            }
            cornerButtons
        }
        // The player floats over the page's foot while the letter is read.
        .overlay(alignment: .bottom) {
            ListenHost(listen) { c in ListenBar(controls: c, colors: ink.listenColors) }
                .padding(.horizontal, 20)
        }
        .sheet(item: $earlierOpened) { earlier in LetterArchiveView(opening: earlier, known: letters) }
        .quickLookPreview($pdfFile)
        .onAppear {
            ReadingAppearance.shared.refresh()
            let next = ListenReading(pieces: ReaderListen.letter(letter))
            if next != listen { listen = next }
        }
        // Closing the letter (or turning to another) stops the voice; going
        // to the background does not.
        .onDisappear { ReadAloud.shared.leave(listen.key) }
        .onAppear {
            guard letter.isUnread else { return }
            Task { _ = try? await MemberAPI.markLetterRead(letter.letterId); onRead() }
        }
        .task {
            // "Last week: …" — quietly absent when the archive doesn't answer.
            if !archive.isEmpty { letters = archive; return }
            if let all = try? await MemberAPI.letters() { letters = all }
        }
    }

    /// Listen and the night page in the top-left corner, Close in the
    /// top-right — the same circles, all clear of the masthead between them.
    private var cornerButtons: some View {
        HStack(spacing: 8) {
            readingButtons
            Spacer(minLength: 0)
            Button {
                Haptics.tap(); dismiss()
            } label: {
                cornerCircle(.x)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16).padding(.top, 14)
    }

    private var readingButtons: some View {
        HStack(spacing: 8) {
            ListenHost(listen) { c in
                if c.available {
                    Button {
                        Haptics.tap()
                        ReadAloud.shared.toggle(c.reading)
                    } label: {
                        cornerCircle(c.glyph)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(c.label)
                }
            }
            Button {
                Haptics.tap()
                let next = ReadingTheme.toggled(currentlyNight: night)
                withAnimation(.easeInOut(duration: 0.25)) { readingTheme = next.rawValue }
            } label: {
                cornerCircle(night ? .sun : .moon)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(ReadingTheme.toggleLabel(night: night))
        }
    }

    private func cornerCircle(_ icon: Lucide) -> some View {
        Icon(icon, size: 14, color: ink.navy)
            .frame(width: 34, height: 34)
            .background(ink.card, in: Circle())
            .overlay(Circle().stroke(ink.hairline, lineWidth: 1))
            .contentShape(Circle())
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0xE8CA6C), Color(hex: 0xB6862F)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 30, height: 30)
                    Text("N").font(.fraunces(15, .semibold)).foregroundStyle(Color(hex: 0x1E2A1F))
                }
                .nuruFixedFigure()
                .accessibilityHidden(true)
                Text("NURU PLACE").font(.inter(11, .bold)).kerning(1.8).foregroundStyle(ink.gold)
            }
            Text("The Sunday Letter")
                .font(.frauncesItalic(34))   // the masthead (an editorial size — TypeScan.listed)
                .foregroundStyle(ink.navy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .nuruDisplayType()
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 3) {
                Rectangle().fill(ink.rule).frame(height: 1)
                Rectangle().fill(ink.rule).frame(height: 1)
            }
            .accessibilityHidden(true)
            let line = LetterEditorialWords.dateline(issueNo: letter.issueNo, weekOf: letter.weekOf)
            if !line.isEmpty {
                Text(line.uppercased()).font(.inter(11)).kerning(1.2).foregroundStyle(ink.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }

    // MARK: Hero

    @ViewBuilder private var hero: some View {
        switch LetterEditorialWords.hero(letter) {
        case let .photo(url, alt, caption) where !photoFailed:
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 270)
                    .overlay {
                        CachedAsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else if phase.error != nil {
                                // A photograph that doesn't come gives way to the art.
                                Color.clear.onAppear { photoFailed = true }
                            } else {
                                ink.verse.opacity(0.6)
                            }
                        }
                    }
                    .clipped()
                    .accessibilityElement()
                    .accessibilityLabel(alt ?? "The week's photograph")
                    .accessibilityAddTraits(.isImage)
                if let caption {
                    Text(caption)
                        .font(.frauncesItalic(12)).foregroundStyle(ink.muted)
                        .nuruLineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24).padding(.top, 8)
                }
            }
            .padding(.bottom, 6)
        case .photo:
            LetterHero(imageKey: letter.imageKey, height: 270)
        case let .art(key):
            LetterHero(imageKey: key, height: 270)
        }
    }

    // MARK: The page

    private var page: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(letter.title)
                    .font(.fraunces(28, .semibold)).foregroundStyle(ink.navy)
                    .nuruLineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .nuruWholeWords(letter.title, font: .fraunces(28, .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(LetterEditorialWords.dek(readingMinutes: letter.readingMinutes))
                    .font(.inter(13)).foregroundStyle(ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(letter.salutation)
                .font(.frauncesItalic(22)).foregroundStyle(ink.navy)
                .fixedSize(horizontal: false, vertical: true)
            if let first = paragraphs.first { openingParagraph(first) }
            if let line = letter.shareLine { pullQuote(line) }
            ForEach(Array(paragraphs.dropFirst().enumerated()), id: \.offset) { _, p in paragraph(p) }
            if LetterEditorialWords.showsWeek(letter) { weekCard }
            if let s = LetterEditorialWords.scripture(letter) { scriptureCard(s) }
            if let step = letter.nextStep { stepBand(step) }
            signature
            footer
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.fraunces(18, .regular)).foregroundStyle(ink.body)
            .nuruLineSpacing(Self.bodySpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The first paragraph with its gold drop cap — or plain at the
    /// accessibility sizes, where three large lines beside a cap would squeeze
    /// the words, and for a paragraph that doesn't open on a letter.
    @ViewBuilder private func openingParagraph(_ text: String) -> some View {
        if !typeSize.isAccessibilitySize, let split = LetterDropCap.split(text) {
            LetterDropCapParagraph(initial: split.initial, rest: split.rest, spoken: text,
                                   lineSpacing: Self.bodySpacing * Nuru.lineSpacing, night: night)
        } else {
            paragraph(text)
        }
    }

    /// The one shareable line, between gold rules, with "Share this line".
    private func pullQuote(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LetterEditorialWords.pullQuote(line))
                .font(.frauncesItalic(22)).foregroundStyle(ink.gold)
                .nuruLineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                ShareLink(item: line) {
                    HStack(spacing: 6) {
                        Icon(.share2, size: 14, color: ink.gold)
                        Text("Share this line").font(.inter(13, .semibold)).foregroundStyle(ink.gold)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 36)
                    .overlay(Capsule().stroke(ink.gold.opacity(0.5), lineWidth: 1))
                    .contentShape(Capsule())
                }
            }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Rectangle().fill(ink.rule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(ink.rule).frame(height: 1) }
        .padding(.vertical, 4)
    }

    // MARK: Your week, in grace

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR WEEK, IN GRACE").font(.inter(11, .bold)).kerning(1.8).foregroundStyle(ink.gold)
                .fixedSize(horizontal: false, vertical: true)
            if !letter.figures.isEmpty {
                // Three across at the everyday sizes; one above another at the
                // largest, where a column couldn't hold a figure (§9.6 #4).
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(letter.figures.enumerated()), id: \.offset) { _, f in figure(f) }
                    }
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(letter.figures.enumerated()), id: \.offset) { _, f in figure(f) }
                    }
                }
            }
            if !letter.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(letter.highlights, id: \.self) { h in
                        HStack(alignment: .top, spacing: 10) {
                            Icon(.check, size: 14, color: ink.gold).padding(.top, 2)
                            Text(h).font(.inter(13)).foregroundStyle(ink.body)
                                .nuruLineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 18).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ink.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ink.hairline, lineWidth: 1))
    }

    private func figure(_ f: LetterFigure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(f.value)
                .font(.fraunces(34, .medium))   // a figure (an editorial size — TypeScan.listed)
                .foregroundStyle(ink.navy)
                .nuruLineLimit(1).minimumScaleFactor(0.6)
                .nuruDisplayType()
            if !f.label.isEmpty {
                Text(f.label).font(.inter(12)).foregroundStyle(ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(ink.gold.opacity(0.35)).frame(width: 1) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Scripture

    private func scriptureCard(_ s: LetterScripture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let text = s.text {
                Text("\u{201C}")
                    .font(.fraunces(44))   // the opening quote (an editorial size — TypeScan.listed)
                    .foregroundStyle(ink.rule)
                    .nuruDisplayType()
                    .frame(height: 30, alignment: .top)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.frauncesItalic(18)).foregroundStyle(ink.navy)
                    .nuruLineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LetterEditorialWords.scriptureKicker(s).uppercased())
                    .font(.inter(11, .bold)).kerning(1.8).foregroundStyle(ink.gold)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // No stored text for the reference: the reference alone.
                Text("SCRIPTURE").font(.inter(11, .bold)).kerning(1.8).foregroundStyle(ink.gold)
                Text(LetterEditorialWords.scriptureKicker(s))
                    .font(.fraunces(18, .semibold)).foregroundStyle(ink.navy)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 22).padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ink.verse, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: One step for this week

    private func stepBand(_ step: LetterNextStep) -> some View {
        Button {
            Haptics.action()
            navigate(step)
            dismiss()
        } label: {
            NuruNextStepBand(icon: .bookOpen, kicker: "ONE STEP FOR THIS WEEK", title: step.label,
                             verb: LetterEditorialWords.verb(step))
        }
        .buttonStyle(.pressableSubtle)
    }

    /// The letter's one step lands where Home's next action does: a lesson by
    /// its id, else the Pathway tab.
    private func navigate(_ step: LetterNextStep) {
        if step.route == "module", let id = step.params?.moduleId, !id.isEmpty {
            tabs.openPathway(.module(id))
        } else {
            tabs.selected = .pathway
        }
    }

    // MARK: Signature

    private var signature: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("With grace,").font(.frauncesItalic(15)).foregroundStyle(ink.muted)
            Text(signer.name)
                .font(.custom("MrsSaintDelafield-Regular", size: 52 * Nuru.textScale))   // the signature (an editorial size — TypeScan.listed)
                .foregroundStyle(ink.navy)
                .fixedSize(horizontal: false, vertical: true)
                // A script face's line is deep (ascender 906, descender −619
                // per 1000) while a name's ink sits on its baseline: drawn on
                // board A's 56 pt line, the role follows the hand closely.
                .padding(.top, -6).padding(.bottom, -16)
                .nuruDisplayType()
            if let role = signer.role {
                Text(role.uppercased()).font(.inter(11, .bold)).kerning(1.8).foregroundStyle(ink.gold)
            }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(ink.hairline).frame(height: 1)
            footerRow(.penLine, LetterEditorialWords.writeBackLabel, busy: openingThread) { writeBack() }
            if letter.pdfUrl != nil {
                footerRow(.fileText, "Keep this letter as a PDF", busy: fetchingPDF) { keepPDF() }
            }
            if let row = LetterEditorialWords.lastWeek(letter, in: letters) {
                // That letter itself (owner, 2026-10-07: as on Android) —
                // whose own row goes on further back.
                footerRow(.bookOpen, row.label) { Haptics.tap(); openEarlierLetter(row.opens) }
            }
            if let actionLine {
                Text(actionLine).font(.nCardMeta).foregroundStyle(ink.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }

    private func footerRow(_ icon: Lucide, _ label: String, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(icon, size: 18, color: ink.gold)
                Text(label).font(.inter(14, .medium)).foregroundStyle(ink.navy)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if busy {
                    ProgressView().tint(ink.gold)
                } else {
                    Icon(.chevronRight, size: 14, color: ink.chevron)
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 2)
            .overlay(alignment: .bottom) { Rectangle().fill(ink.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .disabled(busy)
    }

    /// "Last week" opens that letter: in place inside the archive, else the
    /// archive opened on it (its list behind it).
    private func openEarlierLetter(_ earlier: PastoralLetter) {
        if let openEarlier { openEarlier(earlier) } else { earlierOpened = earlier }
    }

    /// The member's own pastoral conversation (create-or-open) — their
    /// assigned pastor's — behind the same privacy gate the Pastor tab uses.
    private func writeBack() {
        guard !openingThread else { return }
        Haptics.tap()
        actionLine = nil
        Task {
            if PastoralLock.shared.requiresUnlock, !(await PastoralLock.shared.unlock()) { return }
            openingThread = true
            defer { openingThread = false }
            do {
                let t = try await MemberAPI.openPastoralThread()
                PastoralPrefs.pastoralConversationId = t.conversationId
                PastoralPrefs.archived = false   // opening it un-archives by intent
                dismiss()
                tabs.openConversation(t.conversationId)
            } catch {
                actionLine = LetterEditorialWords.writeBackFailure(error)
            }
        }
    }

    /// The letter as its one-page A4: fetched with the session, kept as a
    /// file, shown in Quick Look (whose share sheet saves or sends it).
    private func keepPDF() {
        guard let path = letter.pdfUrl, !fetchingPDF else { return }
        Haptics.tap()
        actionLine = nil
        fetchingPDF = true
        Task {
            defer { fetchingPDF = false }
            do {
                let data = try await APIClient.shared.download(serverPath: path)
                guard data.starts(with: Array("%PDF".utf8)) else { throw APIError.decoding("not a PDF") }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(LetterEditorialWords.pdfFileName(letter))
                try data.write(to: url, options: .atomic)
                pdfFile = url
            } catch {
                actionLine = NuruStateCopy.failureLine("Couldn't fetch the letter's PDF.", error)
            }
        }
    }
}

// MARK: - The drop cap

/// The first paragraph with its drop cap: the initial in gold Fraunces
/// display type, two lines deep, the paragraph flowing around it — TextKit's
/// exclusion path, the float board A was drawn with. One accessibility
/// element: VoiceOver reads the paragraph whole.
struct LetterDropCapParagraph: UIViewRepresentable {
    let initial: String
    let rest: String
    let spoken: String
    let lineSpacing: CGFloat
    /// The night page's ink (the reading theme) — board A's by day.
    var night: Bool = false

    func makeUIView(context: Context) -> LetterDropCapView { LetterDropCapView() }

    func updateUIView(_ view: LetterDropCapView, context: Context) {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(context.environment.dynamicTypeSize))
        view.configure(initial: initial, rest: rest, spoken: spoken,
                       body: Self.bodyFont(traits), capFace: Self.capFace(), lineSpacing: lineSpacing,
                       ink: UIColor(night ? LetterInk.nightBody : LetterInk.dayBody),
                       gold: UIColor(night ? LetterInk.nightGold : LetterInk.dayGold))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LetterDropCapView, context: Context) -> CGSize? {
        guard let w = proposal.width, w.isFinite, w > 0 else { return nil }
        return CGSize(width: w, height: uiView.height(forWidth: w))
    }

    /// The reading text as SwiftUI sets it beside it: Fraunces 18, the
    /// member's text size, scaled with the phone's like `.fraunces(18)`.
    static func bodyFont(_ traits: UITraitCollection) -> UIFont {
        UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: Nuru.uiFont("Fraunces-Regular", 18, scaled: true), compatibleWith: traits)
    }

    /// The initial's face — sized at layout to span the cap's lines.
    static func capFace() -> UIFont {
        Nuru.uiFont("Fraunces-SemiBold", 58, scaled: true)   // the drop cap (an editorial size — TypeScan.listed)
    }
}

final class LetterDropCapView: UIView {
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)
    private var cap = NSAttributedString()
    private var capFont: UIFont?
    private var bodyFont: UIFont?
    private var spacing: CGFloat = 0
    private var capOrigin = CGPoint.zero
    private var laidOutWidth: CGFloat = -1
    private var contentHeight: CGFloat = 0


    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    required init?(coder: NSCoder) { nil }

    func configure(initial: String, rest: String, spoken: String, body: UIFont, capFace: UIFont, lineSpacing: CGFloat,
                   ink: UIColor, gold: UIColor) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        storage.setAttributedString(NSAttributedString(string: rest, attributes: [
            .font: body, .foregroundColor: ink, .paragraphStyle: para,
        ]))
        // The initial's cap height runs from the first line's cap height down
        // to the last spanned line's baseline.
        let lineHeight = body.lineHeight + lineSpacing
        let wanted = lineHeight * CGFloat(LetterDropCap.lines - 1) + body.capHeight
        let ratio = capFace.capHeight / capFace.pointSize
        let font = capFace.withSize(ratio > 0 ? wanted / ratio : capFace.pointSize)
        cap = NSAttributedString(string: initial, attributes: [.font: font, .foregroundColor: gold])
        capFont = font
        bodyFont = body
        spacing = lineSpacing
        accessibilityLabel = spoken
        laidOutWidth = -1
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        layoutText(width: width)
        return contentHeight
    }

    private func layoutText(width: CGFloat) {
        guard width > 0, width != laidOutWidth, let body = bodyFont, let capFont else { return }
        laidOutWidth = width
        let lineHeight = body.lineHeight + spacing
        let capWidth = ceil(cap.size().width)
        container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        container.exclusionPaths = [UIBezierPath(rect: CGRect(
            x: 0, y: 0, width: capWidth + LetterDropCap.gap,
            height: lineHeight * CGFloat(LetterDropCap.lines) - 1))]
        layoutManager.ensureLayout(for: container)
        // The baselines of the spanned lines, as TextKit set them.
        var baselines: [CGFloat] = []
        let glyphs = layoutManager.glyphRange(for: container)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, range, stop in
            baselines.append(rect.minY + self.layoutManager.location(forGlyphAt: range.location).y)
            if baselines.count >= LetterDropCap.lines { stop.pointee = true }
        }
        let first = baselines.first ?? body.ascender
        let capBaseline = baselines.count >= LetterDropCap.lines
            ? baselines[LetterDropCap.lines - 1]
            : first + lineHeight * CGFloat(LetterDropCap.lines - 1)
        capOrigin = CGPoint(x: 0, y: capBaseline - capFont.ascender)
        let used = layoutManager.usedRect(for: container)
        contentHeight = ceil(max(used.maxY, capBaseline + 2))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutText(width: bounds.width)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        layoutText(width: bounds.width)
        cap.draw(at: capOrigin)
        let glyphs = layoutManager.glyphRange(for: container)
        layoutManager.drawBackground(forGlyphRange: glyphs, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
    }
}
