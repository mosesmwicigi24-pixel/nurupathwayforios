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
    static let metaGray  = Color(hex: 0x5B6472)   // secondary text
    static let faintGray = Color(hex: 0x74808F)   // tertiary text
    static let subGray   = Color(hex: 0x59667C)   // header subtitle gray
    static let priorityBg = Color(hex: 0xFFFAEC)  // PriorityStrip tint
    static let liveRed   = Color(hex: 0xDC2626)
}

// MARK: - Fade-in network image (success phase settles in instead of popping)

/// Wraps the success image of a `CachedAsyncImage` phase closure so freshly
/// loaded artwork fades in over ~0.25s. Warm-cache hits fade too — fast enough
/// to read as "settling", never as "loading".
///
/// Layout-safe by construction: `Color.clear` owns the layout size and the
/// fill image lives in an overlay, so its oversized "fill" size can never
/// inflate the container (the radio-screen edge-spill bug family). Every call
/// site either sits in an overlay position or gets an explicit frame, so
/// reporting the proposed size (not an intrinsic one) is always correct.
struct HomeFadeInImage: View {
    let image: Image
    var maxOpacity: Double = 1
    @State private var shown = false
    var body: some View {
        Color.clear
            .overlay {
                image.resizable().scaledToFill()
                    .opacity(shown ? maxOpacity : 0)
            }
            .clipped()
            .onAppear {
                guard !shown else { return }
                withAnimation(.easeOut(duration: 0.25)) { shown = true }
            }
    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var isLive: Bool { startsInMin == nil }

    var body: some View {
        VStack(spacing: 0) {
            media
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.nCardTitle).foregroundStyle(.white)
                    .lineLimit(3).truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                metaRow.padding(.top, 4)
                Button { Haptics.tap(); onOpen() } label: {
                    HStack(spacing: 8) {
                        if isLive { Icon(.play, size: 15, color: HomeFig.navy) }
                        else { Image(systemName: "bell.badge.fill").font(.system(size: 14)).foregroundStyle(HomeFig.navy) }
                        Text(isLive ? "Watch live" : "Set reminder")
                            .font(.nCardCTA).foregroundStyle(HomeFig.navy)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(HomeFig.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
        }
        .background(HomeFig.navy)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .onAppear {
            guard !reduceMotion else { return }   // pulses are decoration only
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
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
                        if let img = phase.image { HomeFadeInImage(image: img, maxOpacity: 0.9) }
                        else { posterFallback }
                    }
                }
            } else {
                posterFallback
            }
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
            Button { Haptics.tap(); onOpen() } label: { playDisc }.buttonStyle(.pressable)
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
                Text(location).font(.nCardMeta).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            if let m = startsInMin {
                Icon(.clock, size: 11, color: .white.opacity(0.7)).padding(.leading, location == nil ? 0 : 6)
                Text("Starts in \(m) min").font(.nCardMeta).foregroundStyle(.white.opacity(0.7))
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
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 12) {
                Icon(.messageSquareText, size: 16, color: HomeFig.gold)
                    .frame(width: 36, height: 36)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy)
                        .lineLimit(2).truncationMode(.tail)
                    Text(meta).font(.nCardMeta).foregroundStyle(HomeFig.metaGray).lineLimit(1)
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
        .buttonStyle(.pressable)
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
        Button { Haptics.tap(); action() } label: {
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
        .buttonStyle(.pressableSubtle)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FOR YOU TODAY").font(.nCardKicker).kerning(1.4).foregroundStyle(HomeFig.gold)
            Text(title)
                .font(.nCardTitle).foregroundStyle(.white)
                .lineLimit(3).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Text(meta).font(.nCardBody).foregroundStyle(.white.opacity(0.55)).lineLimit(2).padding(.top, 4)
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
                Text(note).font(.nCardMeta).foregroundStyle(.white.opacity(0.45)).lineLimit(2).padding(.top, 6)
            }
            HStack(spacing: 6) {
                Text(ctaLabel).font(.nCardCTA).foregroundStyle(HomeFig.navy)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Encouragement ("You're one reflection away…" / "Beautifully done today.")

/// Nuru's daily word in the header — the AI blessing written for this member.
/// A hanging gold quote mark + settled italic serif so it reads as a spoken
/// word, not UI copy. Settles in gently once per appearance.
struct HomePersonalWord: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text("“").font(.fraunces(24, .semibold)).foregroundStyle(HomeFig.gold)
                .offset(y: -2).accessibilityHidden(true)
            Text(text)
                .font(.fraunces(14)).italic()
                .foregroundStyle(Color(hex: 0x475569))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .gentleEntrance()
    }
}

/// The daily exhortation — grounded ONLY in the member's real walk (streak,
/// rhythm, module distance, their cell's prayers) and rotated deterministically
/// by day-of-year so it stays fresh across days but steady within one.
struct HomeEncouragementCard: View {
    let firstName: String
    let streak: Int
    let rhythmDone: Int        // 0–3 of prayer/word/reflection met today
    let wordDone: Bool
    let prayerDone: Bool
    let modulesLeft: Int?      // remaining in the active level (nil = no enrollment)
    let levelNumber: Int?
    let cellPrayerCount: Int   // prayer-wall posts currently on the member's wall feed

    private var line: String {
        var candidates: [String] = []
        if rhythmDone == 3 {
            candidates.append("Beautifully done today, \(firstName) — prayer, word and reflection, all met.")
        }
        if streak >= 2 {
            candidates.append("Day \(streak) of your walk, \(firstName). Small faithfulness is building something eternal.")
        }
        if let left = modulesLeft, let lvl = levelNumber, (1...3).contains(left) {
            candidates.append("Only \(left) module\(left == 1 ? "" : "s") between you and the Level \(lvl) gate, \(firstName).")
        }
        if !wordDone {
            candidates.append("A single verse can reset the whole day — yours is waiting above.")
        }
        if !prayerDone {
            candidates.append("Two quiet minutes with the Father change the next twelve hours.")
        }
        if cellPrayerCount > 0 {
            candidates.append("Your community lifted \(cellPrayerCount) prayer\(cellPrayerCount == 1 ? "" : "s") — stand with one of them today.")
        }
        if candidates.isEmpty {
            candidates.append("You're one reflection away from completing this week's rhythm.")
        }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return candidates[day % candidates.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(.sparkles, size: 16, color: HomeFig.gold)
                .frame(width: 32, height: 32)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(line)
                .font(.fraunces(14)).italic().foregroundStyle(Color(hex: 0x1F2937))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .overlay(alignment: .leading) {
            // A whisper of gold along the spine — this card speaks, not lists.
            RoundedRectangle(cornerRadius: 2).fill(HomeFig.gold.opacity(0.55))
                .frame(width: 3).padding(.vertical, 12)
        }
    }
}

// MARK: - "You're not in a cell yet" belonging cue (cohort cold start)

struct HomeCohortColdStart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .font(.nCardMeta).foregroundStyle(HomeFig.subGray)
            }
            Spacer(minLength: 0)
            Icon(.chevronRight, size: 15, color: HomeFig.faintGray)
        }
        .padding(12)
        .background(LinearGradient(colors: [HomeFig.gold.opacity(0.08), HomeFig.gold.opacity(0.02)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HomeFig.gold.opacity(0.2), lineWidth: 1))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                            if let img = phase.image { HomeFadeInImage(image: img) }
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
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - "Support God's work" give panel (centered ceremony layout)

struct HomeGiveCard: View {
    let action: () -> Void
    var body: some View {
        Button { Haptics.tap(); action() } label: {
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
                        .font(.nCardKicker).kerning(1.4).foregroundStyle(HomeFig.gold)
                        .padding(.top, 12)
                    Text("Sow into something eternal")
                        .font(.fraunces(20, .semibold)).foregroundStyle(.white)
                        .padding(.top, 4)
                    Text("Every gift carries the gospel further — raising disciples, sustaining the mission, and lighting the way for the next person to find Christ. Give cheerfully, as the Lord leads.")
                        .font(.nCardBody).foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    HStack(spacing: 8) {
                        Icon(.handHeart, size: 16, color: HomeFig.navy)
                        Text("Give now").font(.nCardCTA).foregroundStyle(HomeFig.navy)
                        Icon(.chevronRight, size: 16, color: HomeFig.navy)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient(colors: [HomeFig.gold, HomeFig.goldDeep],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 16)
                    Text("Tithe & offering · M-Pesa, card and more")
                        .font(.nCardMeta).foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 10)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .nuruShadow()
        }
        .buttonStyle(.pressableSubtle)
    }
}

// MARK: - Nuru Radio ON AIR bar (pinned FIRST on Home while a broadcast is live)

/// Figma RadioBar — the thin "on air" strip: navy gradient pill with the show's
/// artwork, glowing studio lights + "ON AIR · Nuru Radio", a listeners/loves
/// line, and a gold play-pause disc. The bar IS the remote (RadioCenter powers
/// playback so the Dynamic Island / Lock Screen wave appears on play); tapping
/// anywhere else opens the live studio. Real data only: the listener count only
/// renders when the backend reports one — otherwise the line carries the show's
/// real title.
struct HomeOnAirCard: View {
    let program: RadioProgram
    let onOpen: () -> Void
    @ObservedObject private var radio = RadioCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var isPlayingThis: Bool { radio.program?.id == program.id && radio.playing }
    /// Warm on-air studio art — only when the program carries none of its own.
    private static let fallbackArt =
        URL(string: "https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=400&q=80")

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    art
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            studioLights
                            Text("ON AIR").font(.inter(9, .bold)).kerning(1.44).foregroundStyle(.white)
                            Text("· Nuru Radio").font(.inter(10, .bold)).foregroundStyle(HomeFig.gold)
                        }
                        HStack(spacing: 8) {
                            if let n = program.peakListeners, n > 0 {
                                HStack(spacing: 4) {
                                    Icon(.users, size: 11, color: HomeFig.goldSoft)
                                    Text("\(n) listening").font(.inter(10)).foregroundStyle(.white.opacity(0.7))
                                }
                            } else {
                                Text(program.title).font(.inter(10)).foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            Text("❤️ 🙏 🙌").font(.system(size: 11))
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                Haptics.tap()
                if isPlayingThis { radio.pause() } else { radio.tune(program) }
            } label: {
                Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(HomeFig.navy)
                    .frame(width: 36, height: 36)
                    .background(LinearGradient(colors: [HomeFig.gold, HomeFig.goldDeep],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            }
            .buttonStyle(.pressable)
        }
        .padding(8)
        .background(
            LinearGradient(colors: [HomeFig.navy, HomeFig.navyDark],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.06), lineWidth: 1))
        .shadow(color: Color(hex: 0x0A1628).opacity(0.35), radius: 12, y: 7)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var art: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x16273F), HomeFig.navyDark],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let u = (program.artworkUrl.flatMap(URL.init(string:))) ?? Self.fallbackArt {
                CachedAsyncImage(url: u) { ph in
                    if let img = ph.image { HomeFadeInImage(image: img) }
                    else { Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 14)).foregroundStyle(HomeFig.gold) }
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // Red pulses; amber + green glow steady — the studio lamp trio.
    private var studioLights: some View {
        HStack(spacing: 4) {
            Circle().fill(Color(hex: 0xEF4444)).frame(width: 8, height: 8)
                .shadow(color: Color(hex: 0xEF4444), radius: 4)
                .opacity(pulse ? 0.25 : 1)
            Circle().fill(Color(hex: 0xF59E0B)).frame(width: 8, height: 8)
                .shadow(color: Color(hex: 0xF59E0B), radius: 3)
            Circle().fill(Color(hex: 0x22C55E)).frame(width: 8, height: 8)
                .shadow(color: Color(hex: 0x22C55E), radius: 3)
        }
    }
}


// MARK: - Equalizer wave (Apple-Music-style dancing bars while radio plays)

/// Five capsule bars bouncing on staggered, slightly-detuned loops so the wave
/// reads organic rather than metronomic. Purely decorative — honors Reduce
/// Motion by holding a static mid-height wave.
struct EqualizerWave: View {
    var color: Color = HomeFig.gold
    var barHeight: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dancing = false
    // Each bar's full height as a share of barHeight — an uneven skyline.
    private let peaks: [CGFloat] = [0.55, 1.0, 0.7, 0.9, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(peaks.indices, id: \.self) { i in
                Capsule().fill(color)
                    .frame(width: 3, height: max(3, peaks[i] * barHeight * (dancing ? 1 : 0.3)))
                    .animation(reduceMotion ? nil
                               : .easeInOut(duration: 0.42 + Double(i) * 0.07).repeatForever(autoreverses: true),
                               value: dancing)
            }
        }
        .frame(height: barHeight)
        .onAppear { dancing = true }
    }
}

// MARK: - "New today" pulsing dot (devotional tile in the Grow grid)

struct HomePulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(HomeFig.gold).frame(width: 10, height: 10)
                .scaleEffect(pulse ? 2.2 : 1)
                .opacity(pulse ? 0 : 0.6)
            Circle().fill(HomeFig.gold).frame(width: 10, height: 10)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
