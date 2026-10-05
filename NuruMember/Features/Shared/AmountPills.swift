// Amount choices are pills, everywhere (pathway docs/EXPERIENCE.md §8.1 rule
// 6, §8.2 #7 and #12): full capsules, the chosen one navy with white words,
// the rest white with a hairline. Give's five suggested amounts sit on ONE
// line — content-sized when they fit, sharing the width evenly (their words
// easing a little) when they don't, never wrapping a lone "5,000" onto a row
// of its own. A pledge's six sit three across, two even rows.
//
// One small view of its own (not a closure inside the big screens), so the
// screens' generated types stay shallow.
import SwiftUI

struct NuruAmountPills: View {
    /// The choices, in whatever unit the screen counts (major or minor).
    let amounts: [Int]
    /// The chosen one, if any of them is chosen.
    let selected: Int?
    /// nil: one line. A number: that many across, even widths.
    var columns: Int? = nil
    /// "1,000" for an amount.
    let label: (Int) -> String
    let pick: (Int) -> Void

    var body: some View {
        if let columns, columns > 0 {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(amounts, id: \.self) { v in pill(v, fill: true) }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(amounts, id: \.self) { v in pill(v, fill: false) }
                }
                HStack(spacing: 6) {
                    ForEach(amounts, id: \.self) { v in pill(v, fill: true) }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func pill(_ v: Int, fill: Bool) -> some View {
        let on = selected == v
        return Button {
            guard !on else { return }
            Haptics.selection()
            pick(v)
        } label: {
            Text(label(v))
                .font(.inter(13, .semibold)).foregroundStyle(on ? Nuru.white : Nuru.navy)
                .lineLimit(1).minimumScaleFactor(fill ? 0.75 : 1)
                .padding(.horizontal, fill ? 6 : 14)
                .frame(maxWidth: fill ? .infinity : nil)
                .frame(height: 36)
                .background(on ? Nuru.navy : Nuru.white, in: Capsule())
                .overlay(Capsule().stroke(on ? Color.clear : Nuru.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
