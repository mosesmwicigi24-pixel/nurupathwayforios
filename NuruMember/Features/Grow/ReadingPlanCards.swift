// Plans tab building blocks — small private-ish structs extracted from
// ReadingPlansView so no single body grows large (device demangler crash
// history). Everything here is a 1:1 port of the UPDATED Figma Make source
// (components/PlansTab.tsx): the streak strip, continue-reading row, portrait
// plan card, grid tile, finish-&-earn card, day rows, shimmer/pulse accents
// and a lightweight native confetti burst.
import SwiftUI

// Exact Figma palette (PlansTab.tsx). NAVY/NAVY_DEEP changed in the fresh
// design (#0a1628 / #060f1c); BORDER intentionally stays rgba(10,37,64,0.08).
enum PL {
    static let navy      = Color(hex: 0x0A1628)   // NAVY (fresh)
    static let navyDeep  = Color(hex: 0x060F1C)   // NAVY_DEEP (fresh)
    static let gold      = Color(hex: 0xC9A227)
    static let goldLight = Color(hex: 0xE6C068)
    static let goldDeep  = Color(hex: 0xA8861C)
    static let cream     = Color(hex: 0xF4F0E8)
    static let creamLo   = Color(hex: 0xF1ECE1)
    static let surface   = Color(hex: 0xFBF8F1)
    static let border    = Color(hex: 0x0A2540, alpha: 0.08)
    static let ink2      = Color(hex: 0x59667C)
    static let ink3      = Color(hex: 0x74808F)
    static let catText   = Color(hex: 0x9A7A2A)
    static let blurb     = Color(hex: 0x3A4A5F)
    static let highlight = Color(hex: 0xFFF8E6)   // next-day / scripture card bg
    static let refInk    = Color(hex: 0x7A5A14)   // scripture ref overline
    static let bodyInk   = Color(hex: 0x1B2733)   // devotional body text
    static let chev      = Color(hex: 0xCBD5E1)
    static let ctaDeep   = Color(hex: 0xB6862F)   // gold CTA gradient end
}

// MARK: - plan cover (image with brand-gradient fallback)

struct PLCover: View {
    let plan: ReadingPlanRow
    var body: some View {
        ZStack {
            LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let u = plan.imageUrl.flatMap(URL.init) {
                // Color.clear takes exactly the proposed size; the fill image lives
                // in an overlay so its oversized ideal size can never inflate the
                // layout (the root cause of titles painting outside plan cards).
                Color.clear.overlay {
                    CachedAsyncImage(url: u) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                                .transition(.opacity.animation(.easeOut(duration: 0.25))) // fade in, no pop
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
        .clipped()
    }
}

// MARK: - "N DAYS" cover badge

struct PLDaysBadge: View {
    let days: Int
    var body: some View {
        Text("\(days) DAYS").font(.inter(8, .bold)).kerning(0.96).foregroundStyle(PL.navy)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Color.white.opacity(0.9), in: Capsule())
            .padding(8)
    }
}

// MARK: - shimmer sweep (Plan-of-the-day badge)

struct PLShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var x: CGFloat = -0.8
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.7)
                .offset(x: geo.size.width * x)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false)) { x = 2.2 }
                }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - expanding pulse ring (continue-row play button)

struct PLPulseRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Circle().stroke(PL.gold, lineWidth: 1.5)
            .scaleEffect(on ? 1.4 : 1)
            .opacity(on ? 0 : 0.55)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.7).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

// MARK: - streak strip (cue + reward loop)
// Real data: `count` = GET /me/achievements streak.current; `todayDone` =
// GET /me/rhythm/today `word`. The 7-day badge goal is a client-side constant
// (the design's mock STREAK.goal) — week dots are derived from the streak.

struct PLStreakStrip: View {
    let count: Int
    let todayDone: Bool

    private static let week = ["S", "M", "T", "W", "T", "F", "S"]
    private static let goal = 7
    private var todayIdx: Int { Calendar.current.component(.weekday, from: Date()) - 1 }
    private var toReward: Int { max(Self.goal - count, 0) }
    private var pct: Double { min(Double(count) / Double(Self.goal), 1) }

    private func isDone(_ i: Int) -> Bool {
        if i == todayIdx { return todayDone }
        guard i < todayIdx else { return false }
        let back = max(todayDone ? count - 1 : count, 0)
        return todayIdx - i <= back
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [PL.gold.opacity(0.15), PL.gold.opacity(0.05)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    PLFlame()
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(count == 1 ? "1 day with God" : "\(count) days with God")
                        .font(.inter(14, .bold)).kerning(-0.14).foregroundStyle(PL.navy)
                        .lineLimit(1)
                    // Grace-first tone: an invitation, never loss-aversion or guilt.
                    Text(count > 0 ? "A day at a time — return when you can 🌱" : "Begin your walk today 🌱")
                        .font(.nCardMeta).foregroundStyle(PL.ink2)
                        .lineLimit(2).minimumScaleFactor(0.9)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in weekDot(i) }
                }
            }
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(PL.navy.opacity(0.07))
                        Capsule()
                            .fill(LinearGradient(colors: [PL.gold, PL.goldLight], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * pct))
                    }
                }
                .frame(height: 8)
                HStack(spacing: 4) {
                    Icon(.gift, size: 12, color: PL.catText)
                    Text(toReward == 0 ? "Reward ready!" : "\(toReward) day\(toReward == 1 ? "" : "s") to a badge")
                        .font(.inter(10, .bold)).foregroundStyle(PL.catText)
                }
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PL.border, lineWidth: 1))
        .shadow(color: PL.navy.opacity(0.10), radius: 10, y: 6)
    }

    private func weekDot(_ i: Int) -> some View {
        let done = isDone(i)
        let today = i == todayIdx
        return VStack(spacing: 4) {
            Text(Self.week[i]).font(.inter(8, .bold)).foregroundStyle(PL.ink3)
            ZStack {
                if done {
                    Circle().fill(PL.gold)
                    Icon(.check, size: 11, color: .white)
                } else if today {
                    Circle().fill(Color.white)
                    Circle().stroke(PL.gold, lineWidth: 1.5)
                    PLTodayDot()
                } else {
                    Circle().fill(PL.navy.opacity(0.06))
                }
            }
            .frame(width: 20, height: 20)
        }
    }
}

/// Gently pulsing filled flame (Lucide has only the outline glyph → SF Symbol).
struct PLFlame: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false
    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 18))
            .foregroundStyle(PL.gold)
            .scaleEffect(up ? 1.14 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever()) { up = true }
            }
    }
}

/// The breathing gold dot inside today's (unread) streak circle.
private struct PLTodayDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false
    var body: some View {
        Circle().fill(PL.gold)
            .frame(width: 6, height: 6)
            .scaleEffect(up ? 1.5 : 1)
            .opacity(up ? 0.5 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever()) { up = true }
            }
    }
}

// MARK: - continue-reading row

struct PLContinueRow: View {
    let plan: ReadingPlanRow
    private var total: Int { max(plan.dayCount, 1) }
    private var day: Int { plan.currentDay ?? ((plan.completedDays?.count ?? 0) + 1) }
    private var pct: Double { min(max(Double(day) / Double(total), 0), 1) }

    var body: some View {
        HStack(spacing: 12) {
            PLCover(plan: plan).frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(plan.title).font(.inter(14, .bold)).kerning(-0.14).foregroundStyle(PL.navy).lineLimit(1)
                Text("Today · \(plan.subtitle ?? "Day \(day) of \(total)")")
                    .font(.nCardMeta).foregroundStyle(PL.ink2).lineLimit(1).padding(.top, 2)
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(PL.navy.opacity(0.08))
                            Capsule().fill(PL.gold).frame(width: max(6, geo.size.width * pct))
                        }
                    }
                    .frame(height: 6)
                    Text("Day \(day)/\(total)").font(.inter(9, .semibold)).foregroundStyle(PL.ink2)
                }
                .padding(.top, 8)
            }
            ZStack {
                Circle().fill(PL.gold.opacity(0.10))
                PLPulseRing()
                Image(systemName: "play.fill")
                    .font(.system(size: 13)).foregroundStyle(PL.gold).offset(x: 1)
            }
            .frame(width: 36, height: 36)
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PL.border, lineWidth: 1))
        .shadow(color: PL.navy.opacity(0.10), radius: 10, y: 6)
    }
}

// MARK: - portrait plan card (collection carousels)

struct PLPlanCard: View {
    let plan: ReadingPlanRow
    var body: some View {
        NavigationLink(value: plan) {
            // Size the cover FIRST, then overlay text — every overlay is proposed
            // the 150×200 card size, so the title can never lay out wider than
            // the card. Two lines max, tail truncation, 12pt inset all round.
            PLCover(plan: plan)
                .frame(width: 150, height: 200)
                .overlay(LinearGradient(colors: [Color(hex: 0x081424, alpha: 0.05), Color(hex: 0x081424, alpha: 0.85)],
                                        startPoint: .init(x: 0.5, y: 0.4), endPoint: .bottom))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.title).font(.fraunces(13, .semibold)).foregroundStyle(.white)
                            .lineLimit(2).truncationMode(.tail).multilineTextAlignment(.leading)
                        if let c = plan.category, !c.isEmpty {
                            Text(c.uppercased()).font(.inter(9, .bold)).kerning(0.9).foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .overlay(alignment: .topLeading) { PLDaysBadge(days: plan.dayCount) }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: PL.navy.opacity(0.4), radius: 12, y: 9)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - grid tile (search results)

struct PLPlanTile: View {
    let plan: ReadingPlanRow
    var body: some View {
        NavigationLink(value: plan) {
            VStack(alignment: .leading, spacing: 0) {
                // .fit on the flexible PLCover pins the image region to exactly
                // tile-width × 10/16 — the fill image inside can't inflate it.
                PLCover(plan: plan)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .topLeading) { PLDaysBadge(days: plan.dayCount) }
                    .overlay(alignment: .topTrailing) {
                        if plan.completedAt != nil {
                            Icon(.check, size: 11, color: .white)
                                .frame(width: 22, height: 22).background(PL.gold, in: Circle())
                                .padding(6)
                        }
                    }
                    // Progress rail for a plan in progress.
                    .overlay(alignment: .bottom) {
                        if plan.enrolled, plan.completedAt == nil {
                            let done = plan.completedDays?.count ?? max(0, (plan.currentDay ?? 1) - 1)
                            let pct = plan.dayCount > 0 ? CGFloat(done) / CGFloat(plan.dayCount) : 0
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.black.opacity(0.28))
                                    Rectangle().fill(PL.gold).frame(width: geo.size.width * pct)
                                }
                            }.frame(height: 4)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title).font(.inter(12, .bold)).foregroundStyle(PL.navy)
                        .lineLimit(2).truncationMode(.tail).multilineTextAlignment(.leading)
                    if plan.enrolled, plan.completedAt == nil {
                        Text("Day \(plan.currentDay ?? 1) of \(plan.dayCount)").font(.inter(9, .bold)).kerning(0.5).foregroundStyle(PL.goldDeep).lineLimit(1)
                    } else if plan.completedAt != nil {
                        Text("COMPLETED").font(.inter(9, .bold)).kerning(0.9).foregroundStyle(PL.goldDeep).lineLimit(1)
                    } else if let c = plan.category, !c.isEmpty {
                        Text(c.uppercased()).font(.inter(9, .bold)).kerning(0.9).foregroundStyle(PL.catText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PL.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - "Finish & earn" completion-gift card (plan detail)

struct PLFinishEarnCard: View {
    let category: String?
    let dayCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PL.gold.opacity(0.33), lineWidth: 1)
                    .opacity(glow ? 0.8 : 0.3)
                Image(systemName: "trophy")
                    .font(.system(size: 20)).foregroundStyle(PL.goldLight)
            }
            .frame(width: 48, height: 48)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever()) { glow = true }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("FINISH & EARN").font(.inter(9, .bold)).kerning(1.44).foregroundStyle(PL.goldLight)
                Text("The “\(category ?? "Finisher")” badge")
                    .font(.inter(13, .bold)).kerning(-0.13).foregroundStyle(.white)
                    .lineLimit(2).truncationMode(.tail)
                Text("A little gift for your shelf when you complete all \(dayCount) days.")
                    .font(.nCardMeta).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: PL.navyDeep.opacity(0.45), radius: 14, y: 10)
    }
}

// MARK: - detail "What you'll read" day row

struct PLDetailDayRow: View {
    let day: ReadingPlanDay
    let isNext: Bool
    /// True when a segment ack already told us this day should be open, but
    /// the plan fetch hasn't caught up yet (still landing through the sync
    /// path) — an honest, actionable "still syncing" state rather than the
    /// ordinary "not your turn yet" lock.
    var syncing: Bool = false
    private var done: Bool { day.completed == true }
    /// Not yet opened: an earlier day is still unfinished. Shown quietly — the
    /// road ahead is visible, it just isn't walkable yet.
    private var locked: Bool { day.locked }

    var body: some View {
        HStack(spacing: 12) {
            // The day number is ALWAYS prominent — completion never covers it.
            // Done state = warm gold tint + a small corner check badge instead.
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(done ? PL.gold.opacity(0.16) : Color.white)
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(done ? PL.gold.opacity(0.55) : PL.border, lineWidth: 1)
                    VStack(spacing: -2) {
                        Text("DAY").font(.inter(8, .bold)).kerning(0.9).foregroundStyle(done ? PL.goldDeep : PL.gold)
                        Text("\(day.dayNumber)").font(.fraunces(22, .medium)).foregroundStyle(PL.navy)
                    }
                }
                .frame(width: 52, height: 52)
                if done {
                    Icon(.check, size: 9, color: .white)
                        .frame(width: 17, height: 17)
                        .background(PL.gold, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: 5, y: -5)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(day.title ?? "Reading & reflection").font(.inter(13, .semibold)).foregroundStyle(PL.navy).lineLimit(1)
                Text(done ? "Completed · \(day.reference)"
                     : syncing ? "Finishing your sync… tap to check"
                     : locked ? "\(day.reference) · opens when today is done"
                     : "\(day.reference) · about 6 min")
                    .font(.nCardMeta).foregroundStyle(done ? PL.goldDeep : (syncing ? PL.goldDeep : PL.ink3)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if isNext {
                Text("Start").font(.inter(9, .bold)).foregroundStyle(PL.navy)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(PL.gold, in: Capsule())
            } else if syncing {
                Icon(.clock, size: 13, color: PL.goldDeep)
            } else if locked {
                Icon(.lock, size: 13, color: PL.chev)
            } else {
                Icon(.chevronRight, size: 14, color: PL.chev)
            }
        }
        .padding(10)
        .opacity(locked && !syncing ? 0.55 : 1)   // present, but plainly not yours yet
        .background(isNext ? PL.highlight : PL.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(isNext ? PL.gold.opacity(0.27) : .clear, lineWidth: 1))
    }
}


// MARK: - The plan promo ("an ad, beautifully done")

/// A full-bleed invitation to one plan (owner, 2026-08-26: "make beautiful ads
/// that promote plans with nice images and messages"). Nothing here is
/// invented: the picture is the plan's own cover, and the words are the plan's
/// own subtitle and the opening line of its description — copy already written
/// with care ("Fear is a faithful visitor. It comes at night when the bills are
/// counted…"). The card simply gives them room to be read.
struct PLPlanPromo: View {
    let plan: ReadingPlanRow
    var kicker: String = "WORTH YOUR WEEK"
    /// The server's reason for showing THIS plan to THIS member. When present it
    /// takes the hook's place (same styling) — a sentence about the reader beats
    /// the plan's own opening line.
    var reason: String? = nil

    /// The opening of the plan's description — the hook, never the essay.
    /// A sentence ends at `.!?` only when a SPACE and a capital follow it;
    /// otherwise "the failure at 2 a.m." gets guillotined into "…at 2 a."
    /// (owner screenshot, 2026-08-26). Two sentences fit this card comfortably.
    private var hook: String? {
        guard let d = plan.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty else { return nil }
        let chars = Array(d)
        var out = ""
        var sentences = 0
        var i = 0
        while i < chars.count {
            out.append(chars[i])
            if ".!?".contains(chars[i]) {
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                let after = i + 2 < chars.count ? chars[i + 2] : "A"
                // A real ending: whitespace then a capital (or the text ends).
                if i + 1 >= chars.count || (next.isWhitespace && (after.isUppercase || after.isNumber)) {
                    sentences += 1
                    if sentences >= 2 || out.count >= 110 { break }
                }
            }
            i += 1
        }
        let s = out.trimmingCharacters(in: .whitespaces)
        if s.count >= 30 { return s.count > 190 ? String(s.prefix(187)).trimmingCharacters(in: .whitespaces) + "…" : s }
        return d.count > 170 ? String(d.prefix(167)).trimmingCharacters(in: .whitespaces) + "…" : d
    }

    /// What actually gets printed under the title: the server's reason if it
    /// gave one, otherwise the plan's own opening line.
    private var blurb: String? {
        if let r = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty { return r }
        return hook
    }

    var body: some View {
        NavigationLink(value: plan) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    PLCover(plan: plan)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    LinearGradient(colors: [Color(hex: 0x081424, alpha: 0.05), Color(hex: 0x081424, alpha: 0.55)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        Icon(.sparkles, size: 9, color: PL.navy)
                        Text(kicker).font(.inter(9, .bold)).kerning(1.26).foregroundStyle(PL.navy)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(PL.gold, in: Capsule())
                    .padding(14)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.title)
                        .font(.fraunces(19, .medium)).kerning(-0.3).foregroundStyle(PL.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    if let s = plan.subtitle, !s.isEmpty {
                        Text(s).font(.inter(11.5, .semibold)).foregroundStyle(PL.gold)
                    }
                    if let h = blurb {
                        Text(h)
                            .font(.fraunces(13)).italic().foregroundStyle(PL.ink2)
                            .nuruLineSpacing(4)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    HStack(spacing: 6) {
                        Text(plan.enrolled ? "Continue the journey" : "Begin the journey")
                            .font(.inter(12, .bold)).foregroundStyle(PL.navy)
                        Icon(.arrowRight, size: 13, color: PL.navy)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(PL.gold, in: Capsule())
                    .padding(.top, 6)
                    HStack(spacing: 4) {
                        Icon(.clock, size: 11, color: PL.ink3)
                        Text("\(plan.dayCount) days · a few minutes a day")
                            .font(.inter(10.5)).foregroundStyle(PL.ink3)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PL.gold.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: PL.navyDeep.opacity(0.14), radius: 16, y: 8)
        }
        .buttonStyle(.pressableSubtle)
    }
}
