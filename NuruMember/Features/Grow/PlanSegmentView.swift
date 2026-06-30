// Plan segment — the native port of screens/PlanSegmentScreen.tsx. One day's
// media segment (Watch / Read / Devotional / Talk it Over / Scripture): a 16:9
// media card (with a play overlay for video kinds), a gold overline + Fraunces
// title + body copy, and a pinned bottom bar that pages to the next segment.
// Tapping the play button launches the immersive full-bleed player cover.
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

    /// Gold overline label per segment kind (WATCH / READ / DEVOTIONAL / …).
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

    /// Body copy: the segment's content, falling back to its reference.
    private var bodyText: String? {
        if let c = segment.content, !c.isEmpty { return c }
        if let r = segment.reference, !r.isEmpty { return r }
        return nil
    }

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Nuru.S.base) {
                        mediaCard
                        Text(overline)
                            .font(.inter(11, .semibold)).kerning(1.5)
                            .foregroundStyle(Nuru.gold)
                            .padding(.top, Nuru.S.sm)
                        Text(segment.title)
                            .font(.fraunces(28, .semibold))
                            .foregroundStyle(Nuru.ink)
                        if let body = bodyText {
                            Text(body)
                                .font(.nBodyLg)
                                .foregroundStyle(Nuru.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let scriptureRef = segment.reference,
                           !scriptureRef.isEmpty,
                           scriptureRef != bodyText {
                            Text(scriptureRef)
                                .font(.inter(13, .semibold))
                                .foregroundStyle(Nuru.gold)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.S.xxl)
                }
                bottomBar
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

    // MARK: Header (back arrow + plan title)

    private var header: some View {
        HStack(spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.ink)
                    .frame(width: 38, height: 38)
                    .background(Nuru.white, in: Circle())
                    .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Text(ref.planTitle)
                .font(.inter(15, .semibold))
                .foregroundStyle(Nuru.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.sm)
        .padding(.bottom, Nuru.S.md)
    }

    // MARK: 16:9 media card

    private var mediaCard: some View {
        ZStack {
            mediaBackground
            if isVideo {
                Button { showPlayer = true } label: {
                    ZStack {
                        Circle().fill(Nuru.white).frame(width: 56, height: 56).nuruShadow()
                        Icon(.play, size: 20, color: Nuru.navy)
                            .offset(x: 1) // optically centre the play triangle
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .nuruShadow()
    }

    @ViewBuilder
    private var mediaBackground: some View {
        if let url = segment.imageUrl.flatMap(URL.init) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Nuru.navyGradient)
                }
            }
        } else {
            Rectangle().fill(Nuru.navyGradient)
        }
    }

    // MARK: Pinned bottom bar (Day x · n of N · next)

    private var bottomBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Day \(ref.dayNumber)")
                    .font(.inter(15, .bold))
                    .foregroundStyle(Nuru.ink)
                Text("\(ref.index + 1) of \(ref.segments.count)")
                    .font(.nCaption)
                    .foregroundStyle(Nuru.faint)
            }
            Spacer(minLength: 0)
            nextButton
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.vertical, Nuru.S.base)
        .background(Nuru.paper)
        .overlay(Divider(), alignment: .top)
    }

    @ViewBuilder
    private var nextButton: some View {
        if hasNext {
            NavigationLink(value: nextRef) {
                nextButtonLabel(icon: .chevronRight)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Task { await markComplete() } })
        } else {
            Button { Task { await markComplete(); dismiss() } } label: {
                nextButtonLabel(icon: completed || segment.completed ? .check : .chevronRight)
            }
            .buttonStyle(.plain)
        }
    }

    private func nextButtonLabel(icon: Lucide) -> some View {
        ZStack {
            Circle().fill(Nuru.navyDeep).frame(width: 52, height: 52)
            Icon(icon, size: 20, color: Nuru.onNavy)
        }
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
                    .buttonStyle(.plain)
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
            .buttonStyle(.plain)
        }
    }

    // MARK: Completion (best-effort, non-blocking)

    private func markComplete() async {
        guard !completed, !segment.completed else { completed = true; return }
        _ = try? await MemberAPI.completePlanSegment(segment.segmentId)
        completed = true
    }
}
