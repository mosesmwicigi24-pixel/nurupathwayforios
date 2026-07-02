// HomeCards — the new/updated Home feed cards from the refreshed Figma HomeTab.tsx.
// Every card is its own SMALL struct on purpose: HomeView renders the feed as a
// flat `[AnyView]` array and each card's (deeply-generic) type must be demangled
// one at a time — giant inline VStacks overflow the device's type-metadata
// demangler at launch. Keep additions here, never inline in HomeView's body.
import SwiftUI

// MARK: - Exact Figma HomeTab palette (kept local to Home, matching the design 1:1)

enum HomeFig {
    static let navy      = Color(hex: 0x0A1628)   // Figma NAVY
    static let navyDark  = Color(hex: 0x060F1C)   // gradient bottom
    static let gold      = Color(hex: 0xC89B3C)   // Figma GOLD
    static let goldDeep  = Color(hex: 0xB6862F)   // gradient end
    static let goldSoft  = Color(hex: 0xE6C068)   // progress-bar highlight
    static let eyebrow   = Color(hex: 0x9A7A2A)   // section labels / kickers
    static let metaGray  = Color(hex: 0x6B7280)   // secondary text
    static let faintGray = Color(hex: 0x9CA3AF)   // tertiary text
    static let subGray   = Color(hex: 0x68758A)   // header subtitle gray
    static let priorityBg = Color(hex: 0xFFFAEC)  // PriorityStrip tint
    static let liveRed   = Color(hex: 0xDC2626)
}

// MARK: - Section label ("GROW YOUR FAITH", "UPCOMING", "YOUR COHORT")

struct HomeSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.inter(11, .bold)).kerning(1.98)
            .foregroundStyle(HomeFig.eyebrow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

// MARK: - Live Now (navy media card; `startsInMin == nil` means live right now)

struct HomeLiveNowCard: View {
    let title: String
    let location: String?
    let posterUrl: String?
    let startsInMin: Int?     // nil → live; else "starts soon" variant
    let onOpen: () -> Void
    @State private var pulse = false

    private var isLive: Bool { startsInMin == nil }

    var body: some View {
        VStack(spacing: 0) {
            media
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.fraunces(18, .semibold)).foregroundStyle(.white)
                    .lineLimit(3).truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                metaRow.padding(.top, 4)
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        if isLive { Icon(.play, size: 15, color: HomeFig.navy) }
                        else { Image(systemName: "bell.badge.fill").font(.system(size: 14)).foregroundStyle(HomeFig.navy) }
                        Text(isLive ? "Watch live" : "Set reminder")
                            .font(.inter(14, .semibold)).foregroundStyle(HomeFig.navy)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(HomeFig.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
        }
        .background(HomeFig.navy)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true } }
    }

    // 16:9 poster with LIVE pill, ON AIR studio lights, and the gold play disc.
    private var media: some View {
        ZStack {
            Rectangle().fill(Color.black)
            if let s = posterUrl, let u = URL(string: s) {
                // Contained fill image — a portrait/oversized poster must never
                // inflate the 16:9 media box (same overflow class as plan cards).
                Color.clear.overlay {
                    CachedAsyncImage(url: u) { phase in
                        if let img = phase.image { img.resizable().scaledToFill().opacity(0.9) }
                        else { posterFallback }
                    }
                }
            } else {
                posterFallback
            }
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
            Button(action: onOpen) { playDisc }.buttonStyle(.plain)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) { statusBadge.padding(12) }
        .overlay(alignment: .topTrailing) { if isLive { onAirChip.padding(12) } }
    }

    private var posterFallback: some View {
        ZStack {
            HomeFig.navy
            RadialGradient(colors: [HomeFig.gold.opacity(0.25), .clear],
                           center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 260)
        }
    }

    private var playDisc: some View {
        ZStack {
            Circle().fill(HomeFig.gold).frame(width: 64, height: 64)
                .shadow(color: HomeFig.gold.opacity(0.65), radius: 14, y: 7)
            Circle().stroke(Color.white.opacity(0.28), lineWidth: 4).frame(width: 58, height: 58)
            if isLive { Icon(.play, size: 26, color: HomeFig.navy).offset(x: 2) }
            else { Image(systemName: "bell.badge.fill").font(.system(size: 22)).foregroundStyle(HomeFig.navy) }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            if isLive {
                Circle().fill(.white).frame(width: 6, height: 6).opacity(pulse ? 0.3 : 1)
                Text("LIVE").font(.inter(10, .bold)).kerning(1.6).foregroundStyle(.white)
            } else {
                Icon(.clock, size: 11, color: HomeFig.navy)
                Text("STARTS IN \(startsInMin ?? 0)M").font(.inter(10, .bold)).kerning(1.6).foregroundStyle(HomeFig.navy)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isLive ? HomeFig.liveRed : Color.white.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var onAirChip: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(Color(hex: 0xEF4444)).frame(width: 8, height: 8)
                    .shadow(color: Color(hex: 0xEF4444), radius: 4)
                    .opacity(pulse ? 0.25 : 1)
                Circle().fill(Color(hex: 0xF59E0B)).frame(width: 8, height: 8)
                    .shadow(color: Color(hex: 0xF59E0B), radius: 3)
                Circle().fill(Color(hex: 0x22C55E)).frame(width: 8, height: 8)
                    .shadow(color: Color(hex: 0x22C55E), radius: 3)
            }
            Text("ON AIR").font(.inter(9, .bold)).kerning(1.44).foregroundStyle(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(HomeFig.navy.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    // Location (real, optional) + starts-in line. Viewer counts are intentionally
    // omitted — no live-stream endpoint exists, so there is no real number to show.
    private var metaRow: some View {
        HStack(spacing: 6) {
            if let location, !location.isEmpty {
                Circle().fill(Color.white.opacity(0.5)).frame(width: 4, height: 4)
                Text(location).font(.inter(12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            if let m = startsInMin {
                Icon(.clock, size: 11, color: .white.opacity(0.7)).padding(.leading, location == nil ? 0 : 6)
                Text("Starts in \(m) min").font(.inter(12)).foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Priority strip ("Reflection due today · <module> — Start reflection")

struct HomePriorityStrip: View {
    let title: String
    let meta: String
    let cta: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(.messageSquareText, size: 16, color: HomeFig.gold)
                    .frame(width: 36, height: 36)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy)
                        .lineLimit(2).truncationMode(.tail)
                    Text(meta).font(.inter(11)).foregroundStyle(HomeFig.metaGray).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(cta)
                    .font(.inter(11, .semibold)).foregroundStyle(HomeFig.gold)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(HomeFig.navy, in: Capsule())
            }
            .padding(12)
            .background(HomeFig.priorityBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(HomeFig.gold.opacity(0.33), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - "For you today" resume hero (navy, gold accent bar, progress + pct)

struct HomeResumeHero: View {
    let title: String
    let meta: String
    let pct: Int
    let note: String?
    let ctaLabel: String
    let action: () -> Void

    private var clamped: Int { min(max(pct, 0), 100) }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [HomeFig.navy, HomeFig.navyDark],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(RadialGradient(colors: [HomeFig.gold.opacity(0.33), .clear],
                                         center: .center, startRadius: 0, endRadius: 80))
                    .frame(width: 144, height: 144)
                    .offset(x: 40, y: -48)
                    .blur(radius: 18)
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [HomeFig.gold, Color(hex: 0xA87F29)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 4)
                    .padding(.vertical, 12)
            }
            .nuruShadow()
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FOR YOU TODAY").font(.inter(10, .bold)).kerning(2).foregroundStyle(HomeFig.gold)
            Text(title)
                .font(.fraunces(18, .semibold)).foregroundStyle(.white)
                .lineLimit(3).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Text(meta).font(.inter(12.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(2).padding(.top, 4)
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16)).frame(height: 6)
                        Capsule()
                            .fill(LinearGradient(colors: [HomeFig.gold, HomeFig.goldSoft], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(clamped) / 100, height: 6)
                    }
                }
                .frame(height: 6)
                Text("\(clamped)%").font(.inter(10, .semibold)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 12)
            if clamped >= 60 {
                Text("Almost there — finish strong 🎉")
                    .font(.inter(11, .semibold)).foregroundStyle(HomeFig.goldSoft).padding(.top, 6)
            } else if let note, !note.isEmpty {
                Text(note).font(.inter(11)).foregroundStyle(.white.opacity(0.45)).lineLimit(2).padding(.top, 6)
            }
            HStack(spacing: 6) {
                Text(ctaLabel).font(.inter(13, .bold)).foregroundStyle(HomeFig.navy)
                Icon(.chevronRight, size: 15, color: HomeFig.navy)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(LinearGradient(colors: [HomeFig.gold, HomeFig.goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16).padding(.trailing, 16).padding(.leading, 20)
    }
}

// MARK: - Weekly consistency chain (M–S dots inside "Today's rhythm")

struct HomeWeekChain: View {
    let streakDays: Int
    let todayDone: Bool
    @State private var pulse = false
    private static let days = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        // Monday-first index of today (Sun=6).
        let todayIdx = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let isToday = i == todayIdx
                let isPastDone = i < todayIdx && todayIdx - i <= streakDays
                let isDone = isPastDone || (isToday && todayDone)
                VStack(spacing: 4) {
                    Text(Self.days[i]).font(.inter(9, .bold)).foregroundStyle(Color(hex: 0xB8BFC9))
                    ZStack {
                        if isDone {
                            Circle().fill(HomeFig.gold)
                            Icon(.check, size: 12, color: .white)
                        } else if isToday {
                            Circle().fill(Color.white)
                            Circle().stroke(HomeFig.gold, lineWidth: 1.5)
                            Circle().fill(HomeFig.gold).frame(width: 8, height: 8)
                                .scaleEffect(pulse ? 1.5 : 1)
                                .opacity(pulse ? 0.5 : 1)
                        } else {
                            Circle().fill(HomeFig.navy.opacity(0.06))
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

// MARK: - Encouragement ("You're one reflection away…" / "Beautifully done today.")

struct HomeEncouragementCard: View {
    let rhythmComplete: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(.sparkles, size: 16, color: HomeFig.gold)
                .frame(width: 32, height: 32)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(rhythmComplete
                 ? "Beautifully done today."
                 : "You're one reflection away from completing this week's rhythm.")
                .font(.fraunces(14)).italic().foregroundStyle(Color(hex: 0x1F2937))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}

// MARK: - "You're not in a cell yet" belonging cue (cohort cold start)

struct HomeCohortColdStart: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HomeFig.gold.opacity(0.12))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HomeFig.gold.opacity(0.4), lineWidth: 1)
                    .opacity(pulse ? 0.85 : 0.3)
                Icon(.users, size: 15, color: HomeFig.gold)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("You're not in a cell yet").font(.inter(12, .semibold)).foregroundStyle(HomeFig.navy)
                Text("Find your people — grow where your absence is noticed.")
                    .font(.inter(10)).foregroundStyle(HomeFig.subGray)
            }
            Spacer(minLength: 0)
            Icon(.chevronRight, size: 15, color: HomeFig.faintGray)
        }
        .padding(12)
        .background(LinearGradient(colors: [HomeFig.gold.opacity(0.08), HomeFig.gold.opacity(0.02)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HomeFig.gold.opacity(0.2), lineWidth: 1))
        .onAppear { withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

// MARK: - Upcoming card: next-gathering row (thumb · kicker/title/sub · RSVP pill)

struct HomeUpcomingEventRow: View {
    let kicker: String        // "Today · 9:00 AM"
    let soon: Bool            // today/tomorrow → blinking gold dot
    let title: String
    let sub: String           // "3 going" or the location
    let subHighlight: Bool    // gold-bold when it's a going-count
    let imageUrl: String?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.goldChipBg)
                if let s = imageUrl, let u = URL(string: s) {
                    // Contained fill image — keeps the thumb ZStack at exactly
                    // 56×56 so the crop stays centred and nothing paints outside.
                    Color.clear.overlay {
                        CachedAsyncImage(url: u) { phase in
                            if let img = phase.image { img.resizable().scaledToFill() }
                            else { Rectangle().fill(Nuru.mutedBg) }
                        }
                    }
                } else {
                    Icon(.calendarDays, size: 18, color: Nuru.goldChipText)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if soon {
                        Circle().fill(HomeFig.gold).frame(width: 4, height: 4).opacity(pulse ? 0.3 : 1)
                    }
                    Text(kicker).font(.inter(10, .bold)).foregroundStyle(HomeFig.gold).lineLimit(1)
                }
                Text(title).font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy).lineLimit(1)
                Text(sub)
                    .font(.inter(10, subHighlight ? .bold : .regular))
                    .foregroundStyle(subHighlight ? HomeFig.eyebrow : HomeFig.subGray)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("RSVP").font(.inter(9, .bold)).foregroundStyle(HomeFig.gold)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(HomeFig.navy, in: Capsule())
        }
        .padding(10)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

// MARK: - "Support God's work" give panel (centered ceremony layout)

struct HomeGiveCard: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [HomeFig.navy, HomeFig.navyDark],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(RadialGradient(colors: [HomeFig.gold.opacity(0.4), .clear],
                                         center: .center, startRadius: 0, endRadius: 90))
                    .frame(width: 176, height: 176)
                    .offset(x: 48, y: -56)
                    .blur(radius: 26)
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [HomeFig.gold.opacity(0.2), .clear],
                                                 center: .center, startRadius: 0, endRadius: 32))
                            .frame(width: 64, height: 64)
                        Circle()
                            .fill(LinearGradient(colors: [HomeFig.gold, Color(hex: 0xA87F29)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 48, height: 48)
                            .shadow(color: HomeFig.gold.opacity(0.6), radius: 10, y: 6)
                        Icon(.handHeart, size: 24, color: HomeFig.navy)
                    }
                    Text("SUPPORT GOD'S WORK")
                        .font(.inter(10, .bold)).kerning(1.8).foregroundStyle(HomeFig.gold)
                        .padding(.top, 12)
                    Text("Sow into something eternal")
                        .font(.fraunces(20, .semibold)).foregroundStyle(.white)
                        .padding(.top, 4)
                    Text("Every gift carries the gospel further — raising disciples, sustaining the mission, and lighting the way for the next person to find Christ. Give cheerfully, as the Lord leads.")
                        .font(.inter(12.5)).foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    HStack(spacing: 8) {
                        Icon(.handHeart, size: 16, color: HomeFig.navy)
                        Text("Give now").font(.inter(14, .bold)).foregroundStyle(HomeFig.navy)
                        Icon(.chevronRight, size: 16, color: HomeFig.navy)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient(colors: [HomeFig.gold, HomeFig.goldDeep],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 16)
                    Text("Tithe & offering · M-Pesa, card and more")
                        .font(.inter(11)).foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 10)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .nuruShadow()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - "New today" pulsing dot (devotional tile in the Grow grid)

struct HomePulseDot: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(HomeFig.gold).frame(width: 10, height: 10)
                .scaleEffect(pulse ? 2.2 : 1)
                .opacity(pulse ? 0 : 0.6)
            Circle().fill(HomeFig.gold).frame(width: 10, height: 10)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true } }
    }
}
