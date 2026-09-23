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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(S.allCases), id: \.self) { seg in
                    segmentButton(seg, counts[seg] ?? 0)
                }
            }
            .padding(4)
        }
        .background(Color.white.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        .padding(.horizontal, Nuru.S.screen)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, Nuru.S.md)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    private func segmentButton(_ seg: S, _ count: Int) -> some View {
        let selected = selection == seg
        return Button {
            onSelect(seg)
        } label: {
            HStack(spacing: 5) {
                Icon(seg.icon, size: 12, color: selected ? Nuru.gold : Color(hex: 0x59667C))
                Text(seg.label).font(.inter(12, .semibold)).foregroundStyle(selected ? Color.white : Color(hex: 0x59667C))
                // Unread only — a quiet chip (no number) IS "nothing waiting",
                // matching Chat's own segment chips exactly.
                if count > 0 {
                    Text(count > 9 ? "9+" : "\(count)").font(.inter(10, .bold))
                        .foregroundStyle(selected ? Nuru.navy : Color(hex: 0x6A7686))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .frame(minWidth: 18)
                        .background(selected ? Nuru.gold : Nuru.surface, in: Capsule())
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
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
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
