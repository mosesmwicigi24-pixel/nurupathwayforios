// The reading experience, polished (owner ask, 2026-09-04, items 1–3 of five):
//   1. A calmer opening — kicker, the day's title in serif, and an honest
//      "about N min" read from the words actually on the page (the day list's
//      old "about 6 min" was a fixed string).
//   2. Paragraph rhythm — a small gold ornament where the Word ends and the
//      teaching begins.
//   3. Type size — three steps, cycled from the reader header, remembered per
//      device, applied only inside the reader (the app-wide Nuru.textScale
//      still multiplies underneath).
import SwiftUI

// MARK: - Read time

enum ReadTime {
    /// Unhurried devotional reading, not skimming.
    static let wordsPerMinute = 200.0

    static func words(in text: String?) -> Int {
        guard let text else { return 0 }
        return text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    static func minutes(forWords words: Int) -> Int {
        max(1, Int((Double(words) / wordsPerMinute).rounded()))
    }

    /// Everything the member will read on the page — media segments carry
    /// keynotes, not the film, so they are left out.
    static func minutes(for segments: [PlanSegment]) -> Int {
        let words = segments
            .filter { !["video", "audio"].contains($0.kind.lowercased()) }
            .reduce(0) { $0 + Self.words(in: $1.content) }
        return minutes(forWords: words)
    }

    static func minutes(for day: ReadingPlanDay) -> Int {
        if let segs = day.segments, !segs.isEmpty { return minutes(for: segs) }
        return minutes(forWords: words(in: day.content))
    }
}

// MARK: - Reader text size (three steps, cycled)

enum ReaderTextScale {
    static let key = "nuru.readerTextScale"
    static let steps: [Double] = [0.9, 1.0, 1.15]

    /// The step after the current one, wrapping — a value that is not one of
    /// the steps (an old default) moves to the nearest step's successor.
    static func next(after scale: Double) -> Double {
        let i = steps.indices.min(by: { abs(steps[$0] - scale) < abs(steps[$1] - scale) }) ?? 1
        return steps[(i + 1) % steps.count]
    }

    static func label(_ scale: Double) -> String {
        scale < 0.95 ? "Small" : (scale > 1.05 ? "Large" : "Regular")
    }
}

// MARK: - The opening: kicker · title · reference and read time

struct DayOpening: View {
    let title: String?
    let reference: String?
    let minutes: Int
    @Environment(\.readerPalette) private var pal

    private var meta: String {
        var parts: [String] = []
        if let r = reference, !r.isEmpty { parts.append(r) }
        parts.append("about \(minutes) min")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY'S READING").font(.inter(10, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
            if let t = title, !t.isEmpty {
                Text(t).font(.fraunces(pal.fs(24), .medium)).kerning(-0.5).foregroundStyle(pal.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(meta).font(.inter(12, .medium)).foregroundStyle(pal.inkDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The ornament between the Word and the teaching

struct ReaderOrnament: View {
    @Environment(\.readerPalette) private var pal
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(pal.border).frame(height: 1)
            Text("✝").font(.system(size: 12, weight: .medium)).foregroundStyle(pal.gold)
            Rectangle().fill(pal.border).frame(height: 1)
        }
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }
}
