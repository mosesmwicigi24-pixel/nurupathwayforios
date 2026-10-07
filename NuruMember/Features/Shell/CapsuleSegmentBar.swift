// The top-of-tab capsule segmented control — Chat's own row idiom (My Space /
// Chat / My Discipler / My Pastor) lifted one level up, first for the You tab
// (L4) and now shared with the Give tab's Give · Partners pair
// (PARTNERS_PROGRAMME §0). Navy gradient pill when selected, icon + label +
// an optional unread-count chip, sitting in the cream gradient band every
// folded screen used to paint itself. One implementation so the two bars can
// never drift apart in spacing, colour or chip shape.
import SwiftUI

/// A segment the capsule bar can render: a label and a Lucide glyph.
protocol CapsuleSegment: Hashable, CaseIterable {
    var label: String { get }
    var icon: Lucide { get }
}

struct CapsuleSegmentBar<S: CapsuleSegment>: View where S.AllCases: RandomAccessCollection {
    let selection: S
    /// Unread-style counts per segment — a quiet chip when > 0, nothing when 0.
    var counts: [S: Int] = [:]
    let onSelect: (S) -> Void

    var body: some View {
        // Every segment fits, at every size a member can choose (final walk
        // C3: the row scrolled, and "unity" and "Prof" sat cut at its edges).
        // The fullest form that fits is drawn: icons and words; then words
        // alone; then the chosen segment's words with the others' icons —
        // each still named to VoiceOver and shown large on a long press.
        ViewThatFits(in: .horizontal) {
            row(.full)
            row(.words)
            row(.chosenWords)
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        // A bar: its words stop at the largest everyday size; a long press
        // shows a segment large (§9.6 #4).
        .nuruBarText()
        .background(Color.white.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        .padding(.horizontal, Nuru.S.screen)
        .frame(maxWidth: .infinity)
        // Laid out from the safe area's top, right under the status bar; only
        // the band's paint reaches up behind it. (A fixed 60pt top plus the
        // whole bar ignoring the safe area left an empty cream band under the
        // switch — EXPERIENCE.md §6.2.)
        .padding(.top, 8)
        .padding(.bottom, Nuru.S.md)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
                .ignoresSafeArea(edges: .top)
        )
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    /// How much of each segment is drawn.
    enum Form { case full, words, chosenWords }

    private func row(_ form: Form) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(S.allCases), id: \.self) { seg in
                segmentButton(seg, counts[seg] ?? 0, form: form)
            }
        }
        .fixedSize()
    }

    private func segmentButton(_ seg: S, _ count: Int, form: Form) -> some View {
        let selected = selection == seg
        // full: icon and words · words: words alone · chosenWords: the chosen
        // segment's icon and words, the others' icons.
        let showsIcon = form != .words
        let showsWords = form != .chosenWords || selected
        return Button {
            onSelect(seg)
        } label: {
            HStack(spacing: 5) {
                if showsIcon {
                    Icon(seg.icon, size: 14, color: selected ? Nuru.gold : Color(hex: 0x59667C))
                }
                if showsWords {
                    Text(seg.label).font(.inter(12, .semibold)).foregroundStyle(selected ? Color.white : Color(hex: 0x59667C))
                        .lineLimit(1)
                }
                // Unread only — a quiet chip (no number) IS "nothing waiting",
                // matching Chat's own segment chips exactly.
                if count > 0 {
                    Text(count > 9 ? "9+" : "\(count)").font(.inter(11, .bold))
                        .foregroundStyle(selected ? Nuru.navy : Color(hex: 0x6A7686))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .frame(minWidth: 18)
                        .background(selected ? Nuru.gold : Nuru.surface, in: Capsule())
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, form == .full ? 14 : 12)
            .padding(.vertical, 10)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color.clear),
                in: Capsule())
            .shadow(color: selected ? Color(hex: 0x0B1F33).opacity(0.35) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seg.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityShowsLargeContentViewer {
            Icon(seg.icon, size: 22, color: Nuru.navy)
            Text(seg.label)
        }
    }
}
