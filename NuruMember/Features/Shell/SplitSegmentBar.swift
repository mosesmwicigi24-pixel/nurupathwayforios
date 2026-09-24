// A FULL-WIDTH two-half segment control — the Give tab's GIVE · PARTNERS
// switch (Partners UI v2). Unlike CapsuleSegmentBar (the You tab's scrolling
// icon-and-label pills in their own cream band), this is just the control:
// two equal halves on a white capsule track, the selected half navy with
// gold text, no icons, no band. It is the FIRST ROW inside whichever page
// header band hosts it, so the tab paints one band, not two.
//
// Kept separate from CapsuleSegmentBar on purpose: the You tab's four-segment
// capsule must not change, and a "full-width mode" flag on a shared view is
// the kind of thing that drifts. Two small views, two clear jobs.
import SwiftUI

struct SplitSegmentBar<S: CapsuleSegment>: View where S.AllCases: RandomAccessCollection {
    let selection: S
    let onSelect: (S) -> Void

    private static var selectedText: Color { Color(hex: 0xE6CA68) }
    private static var idleText: Color { Color(hex: 0x59667C) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(S.allCases), id: \.self) { seg in
                half(seg)
            }
        }
        .padding(4)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func half(_ seg: S) -> some View {
        let on = selection == seg
        return Button {
            onSelect(seg)
        } label: {
            Text(seg.label.uppercased())
                .font(.inter(13, .semibold)).kerning(1.2)
                .foregroundStyle(on ? Self.selectedText : Self.idleText)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(on ? Nuru.navy : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seg.label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
