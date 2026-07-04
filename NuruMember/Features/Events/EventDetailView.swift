// Event detail — Figma-parity port of the EventDetail make. A full-bleed 16:11
// cover photo hero (parallax stretch, navy scrim, category/live/completed pills,
// serif title), a white content card overlapping the hero with the 2x2 meta grid
// and add-to-calendar/share actions, the "About this gathering" card, the
// "Who's going" avatar rail, the going/maybe/can't RSVP selector, the
// "Who's coming" buzz card with the visual hype composer, a "Check in" button
// for today's/live occurrences that opens the real QR scanner
// (CheckInScannerView → POST /events/{id}/attendance), and a dashed "check-in
// opens when live" notice for future scheduled events. Bound to the real
// /events/{id} + RSVP endpoints; Figma's hardcoded roster drawer and buzz feed
// are mock-only and intentionally not reproduced.
import SwiftUI

@MainActor
final class EventDetailViewModel: ObservableObject {
    @Published var detail: EventDetail?
    @Published var loading = true
    @Published var error: String?
    @Published var rsvpBusy = false
    /// Optimistic RSVP shown immediately (incl. offline) until the server confirms.
    @Published var myRsvpOverride: String?

    private let sync = SyncCoordinator.shared
    let occurrence: CalendarOccurrence
    init(occurrence: CalendarOccurrence) { self.occurrence = occurrence }

    func load() async {
        loading = true; error = nil
        do { detail = try await MemberAPI.event(occurrence.occurrenceId); myRsvpOverride = nil }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load this event." }
        loading = false
    }

    /// Offline-capable RSVP (§C.2): applies optimistically, queues durably, and is
    /// idempotent on the (user, event) row so replays are no-ops.
    func setRsvp(_ status: String) async {
        rsvpBusy = true; defer { rsvpBusy = false }
        myRsvpOverride = status
        await sync.enqueue(domain: "event_rsvps", op: "set", payload: [
            "event_id": AnyCodable(occurrence.occurrenceId),
            "status": AnyCodable(status),
        ])
        if sync.isOnline { await load() }  // refresh authoritative counts + roster
    }

    // ---- Event wall ("Who's coming" buzz posts — GET/POST /events/{id}/posts) ----

    @Published var posts: [EventPost] = []
    @Published var postDraft = ""
    @Published var posting = false

    func loadPosts() async {
        if let fresh = try? await MemberAPI.eventPosts(occurrence.occurrenceId) { posts = fresh }
    }

    /// Post to the wall: optimistic insert, then the real POST (idempotent on the
    /// client-minted post_id + client_mutation_id), then reconcile from the server.
    func submitPost() async {
        let body = postDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !posting else { return }
        posting = true; defer { posting = false }
        let pid = UUID().uuidString
        posts.insert(EventPost(
            postId: pid, authorUserId: "", authorName: "You", authorAvatar: nil,
            body: body, imageUrl: nil, createdAt: ISO8601DateFormatter().string(from: Date()),
            mine: true, rsvpStatus: myRsvpOverride ?? detail?.myRsvp,
            cheerCount: 0, loveCount: 0, myReaction: nil), at: 0)
        postDraft = ""
        do {
            _ = try await MemberAPI.createEventPost(occurrence.occurrenceId, postId: pid, body: body)
            await loadPosts()
        } catch {
            // Roll back the optimistic row and restore the draft so nothing is lost.
            posts.removeAll { $0.postId == pid }
            postDraft = body
            Haptics.error()
        }
    }

    /// One reaction per member per post: tap sets/switches, tapping the held
    /// emoji clears. Optimistic counts, reconciled with the server's response.
    func toggleReaction(_ post: EventPost, kind: String) async {
        guard let i = posts.firstIndex(where: { $0.postId == post.postId }) else { return }
        let newKind: String? = post.myReaction == kind ? nil : kind
        var p = posts[i]
        if p.myReaction == "cheer" { p.cheerCount = max(0, p.cheerCount - 1) }
        if p.myReaction == "love" { p.loveCount = max(0, p.loveCount - 1) }
        if newKind == "cheer" { p.cheerCount += 1 }
        if newKind == "love" { p.loveCount += 1 }
        p.myReaction = newKind
        posts[i] = p
        do {
            let r = try await MemberAPI.reactToEventPost(occurrence.occurrenceId, postId: post.postId, kind: newKind)
            if let j = posts.firstIndex(where: { $0.postId == post.postId }) {
                posts[j].cheerCount = r.cheerCount
                posts[j].loveCount = r.loveCount
                posts[j].myReaction = r.myReaction
            }
        } catch { await loadPosts() }
    }
}

// MARK: - Figma palette for this screen (exact make hexes)

private enum EvD {
    static let paper       = Color(hex: 0xF6F4EE)   // screen background
    static let tile        = Color(hex: 0xFBF8F1)   // inset tiles / secondary buttons
    static let ink         = Color(hex: 0x0A1628)   // primary text
    static let body        = Color(hex: 0x3A4A5F)   // about copy / roster names
    static let secondary   = Color(hex: 0x59667C)   // inactive RSVP text
    static let tertiary    = Color(hex: 0x74808F)   // meta labels / faint text
    static let overline    = Color(hex: 0xA8861C)   // section overlines
    static let gold        = Color(hex: 0xC9A227)
    static let goldDeep    = Color(hex: 0xB6862F)
    static let going       = Color(hex: 0x16A34A)
    static let goingDeep   = Color(hex: 0x15803D)
    static let goingText   = Color(hex: 0x166534)
    static let maybe       = Color(hex: 0xD97706)
    static let declined    = Color(hex: 0x74808F)
    static let navyBase    = Color(hex: 0x0A2540)   // scrim / border / shadow base
    static let border      = Color(hex: 0x0A2540, alpha: 0.07)
    static let borderMid   = Color(hex: 0x0A2540, alpha: 0.10)
    static let composerTop = Color(hex: 0xFFF8E6)
    static let placeholder = Color(hex: 0x9A8C6A)

    /// Deterministic avatar accent for members without a photo (port of colorFor).
    static let avatarPalette: [Color] = [
        Color(hex: 0x0A1628), Color(hex: 0xC9A227), Color(hex: 0x16A34A),
        Color(hex: 0x0EA5E9), Color(hex: 0xA855F7), Color(hex: 0xDC2626),
        Color(hex: 0xD97706),
    ]
    static func avatarAccent(_ seed: String) -> Color {
        var h: UInt32 = 0
        for u in seed.unicodeScalars { h = h &* 31 &+ u.value }
        return avatarPalette[Int(h % UInt32(avatarPalette.count))]
    }
}

// MARK: - Screen

struct EventDetailView: View {
    @StateObject private var vm: EventDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false
    @State private var showVideo = false

    init(occurrence: CalendarOccurrence) {
        _vm = StateObject(wrappedValue: EventDetailViewModel(occurrence: occurrence))
    }

    private var occ: CalendarOccurrence { vm.occurrence }
    private var title: String { vm.detail?.title ?? occ.title }
    private var category: String? { vm.detail?.category ?? occ.category }
    private var location: String? { vm.detail?.location ?? occ.location }
    private var aboutText: String? { vm.detail?.description ?? occ.description }
    private var going: Int { vm.detail?.rsvpCounts.going ?? occ.going }
    private var attendees: [EventAttendee] { vm.detail?.attendees ?? occ.attendees ?? [] }
    private var imageUrl: String? { vm.detail?.primaryImageUrl ?? occ.primaryImageUrl }
    private var isLive: Bool { Ev.isLive(occ.startAt, occ.endAt) }
    private var isCompleted: Bool { !isLive && Ev.date(occ.endAt) < Date() }
    private var isToday: Bool { Calendar.current.isDateInToday(Ev.date(occ.startAt)) }
    /// QR check-in shows for live or same-day occurrences; the server still
    /// enforces qr_enabled / checkin_opens_at, so this is presentation only.
    private var canCheckIn: Bool { (isLive || isToday) && !isCompleted }

    /// What the hero share button and the Share action send.
    private var shareText: String {
        var lines = [title, "\(Ev.weekday(occ.startAt, "EEEE, MMMM d")) · \(Ev.timeRange(occ.startAt, occ.endAt))"]
        if let location, !location.isEmpty { lines.append(location) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                // The content column overlaps the hero by 16 (Figma -mt-4).
                VStack(spacing: -16) {
                    EvdHero(title: title, category: category, imageUrl: imageUrl,
                            isLive: isLive, isCompleted: isCompleted,
                            shareText: shareText, onBack: { dismiss() })
                    content(proxy)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(EvD.paper.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if vm.detail == nil { await vm.load() }
            await vm.loadPosts()
        }
        .fullScreenCover(isPresented: $showScanner) {
            CheckInScannerView(eventId: vm.detail?.eventId ?? occ.occurrenceId,
                               eventTitle: title)
        }
        // Every video opens the ONE universal full-bleed player page.
        .fullScreenCover(isPresented: $showVideo) {
            if let d = vm.detail, let v = d.videoUrl, !v.isEmpty {
                VideoPlayerPage(
                    urlString: v,
                    title: d.title,
                    summary: d.description,
                    quickNote: nil,
                    posterUrl: d.primaryImageUrl)
            }
        }
    }

    private func content(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 12) {
            EvdMetaCard(occ: occ, location: location, going: going,
                        accent: Ev.categoryColor(category), shareText: shareText)
                .gentleEntrance()
            if let d = aboutText, !d.isEmpty { EvdAboutCard(text: d).gentleEntrance(delay: 0.05) }
            // Video + gallery — wire serves video_url and images=[primary,…gallery];
            // the hero already shows images[0], so only extra shots earn the rail.
            if let v = vm.detail?.videoUrl, !v.isEmpty {
                videoTile.gentleEntrance(delay: 0.08)
            }
            if let imgs = vm.detail?.images, imgs.count > 1 {
                EvdGalleryCard(urls: Array(imgs.dropFirst())).gentleEntrance(delay: 0.1)
            }
            if !attendees.isEmpty || going > 0 {
                EvdRosterCard(attendees: attendees, going: going)
                    .gentleEntrance(delay: 0.1)
            }
            EvdRsvpCard(vm: vm)
                .gentleEntrance(delay: 0.15)
            EvdBuzzCard(vm: vm) {
                // Bring the composer above the keyboard once it has settled.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation { proxy.scrollTo("buzzCard", anchor: .top) }
                }
            }
            .id("buzzCard")
            if canCheckIn {
                EvdCheckInButton {
                    Haptics.action()
                    showScanner = true
                }
                .padding(.top, 4)
                .gentleEntrance(delay: 0.2)
            } else if !isLive && !isCompleted {
                EvdCheckInNotice().padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, Nuru.tabBarSpace)
    }

    // Video tile — poster-backed, opens the universal full-bleed player page
    // (never Safari). Mirrors AnnouncementDetailView.
    private var videoTile: some View {
        Button {
            Haptics.tap()
            showVideo = true
        } label: {
            ZStack {
                Nuru.navyGradient.frame(height: 180)
                Icon(.playCircle, size: 48, color: .white)
            }
            .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        }
        .buttonStyle(.pressableSubtle)
    }
}

// MARK: - Gallery rail — fixed-height strip; each photo keeps its natural width.

private struct EvdGalleryCard: View {
    let urls: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EvdOverline("Gallery")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Nuru.S.sm) {
                    ForEach(urls, id: \.self) { s in
                        if let url = URL(string: s) {
                            FitImage(url: url, fixedHeight: 170)
                                .clipShape(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(EvD.border, lineWidth: 1))
    }
}

// MARK: - Hero — 16:11 cover with parallax stretch, scrim, chrome, pills + title.

private struct EvdHero: View {
    let title: String
    let category: String?
    let imageUrl: String?
    let isLive: Bool
    let isCompleted: Bool
    let shareText: String
    let onBack: () -> Void

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let stretch = max(0, minY)          // parallax overscroll
            let h = geo.size.height + stretch
            ZStack(alignment: .bottomLeading) {
                cover
                    .frame(width: geo.size.width, height: h)
                    .clipped()
                    .offset(y: -stretch)
                scrim
                    .frame(width: geo.size.width, height: h)
                    .offset(y: -stretch)
                    .allowsHitTesting(false)
                overlay
            }
            .frame(width: geo.size.width, height: h, alignment: .bottom)
        }
        .aspectRatio(16.0 / 11.0, contentMode: .fit)
    }

    /// Real cover photo when the event has one; brand navy→category gradient otherwise.
    @ViewBuilder private var cover: some View {
        if let s = imageUrl, let url = URL(string: s) {
            CachedAsyncImage(url: url) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else { fallback }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        LinearGradient(colors: [Nuru.navy700, Nuru.navy, Ev.categoryColor(category)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Figma: linear-gradient(180deg, navy .55 → navy .10 @35% → navy .85)
    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: EvD.navyBase.opacity(0.55), location: 0),
            .init(color: EvD.navyBase.opacity(0.10), location: 0.35),
            .init(color: EvD.navyBase.opacity(0.85), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            // top chrome — back (left) + share (right)
            HStack {
                Button(action: onBack) { EvdCircleGlyph(icon: .chevronLeft, size: 20) }
                    .buttonStyle(.pressable)
                Spacer()
                ShareLink(item: shareText) { EvdCircleGlyph(icon: .share2, size: 17) }
                    .buttonStyle(.pressable)
            }
            .padding(.horizontal, 16)
            .padding(.top, 54)   // Figma frames 42; nudged for the real status bar

            Spacer(minLength: 0)

            // bottom — pills + serif title
            VStack(alignment: .leading, spacing: 8) {
                pills
                Text(title)
                    .font(.fraunces(24, .semibold))
                    .kerning(-0.72)                       // -0.03em
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private var pills: some View {
        HStack(spacing: 6) {
            if let c = category {
                Text(c.uppercased())
                    .font(.inter(10, .bold)).kerning(1.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Ev.categoryColor(c).opacity(0.9), in: Capsule())
            }
            if isLive {
                HStack(spacing: 4) {
                    EvdPulseDot(size: 4)
                    Text("LIVE").font(.inter(10, .bold)).kerning(1.4).foregroundStyle(.white)
                }
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(EvD.going, in: Capsule())
            } else if isCompleted {
                Text("COMPLETED")
                    .font(.inter(10, .bold)).kerning(1.4)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.white.opacity(0.2), in: Capsule())
            }
        }
    }
}

/// 40pt frosted circle for the hero chrome (Figma bg-white/15 + backdrop-blur).
private struct EvdCircleGlyph: View {
    let icon: Lucide
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Color.white.opacity(0.15))
            Icon(icon, size: size, color: .white)
        }
        .frame(width: 40, height: 40)
    }
}

/// Small white dot that pulses forever (the Live / Buzzing indicator).
private struct EvdPulseDot: View {
    var size: CGFloat = 4
    @State private var dim = false

    var body: some View {
        Circle().fill(.white)
            .frame(width: size, height: size)
            .opacity(dim ? 0.3 : 1)
            .scaleEffect(dim ? 0.8 : 1)
            .onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever()) { dim = true } }
    }
}

// MARK: - Meta card — 2x2 grid + add-to-calendar / share actions (one card).

private struct EvdMetaCard: View {
    let occ: CalendarOccurrence
    let location: String?
    let going: Int
    let accent: Color
    let shareText: String

    var body: some View {
        VStack(spacing: 12) {
            grid
            actions
        }
        .evdCard(shadow: true)
    }

    private var grid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                EvdMetaTile(icon: .calendarDays, label: "Date",
                            value: Ev.weekday(occ.startAt, "EEEE, MMMM d"), accent: accent)
                EvdMetaTile(icon: .clock, label: "Time",
                            value: Ev.timeRange(occ.startAt, occ.endAt), accent: accent)
            }
            HStack(spacing: 8) {
                EvdMetaTile(icon: .mapPin, label: "Where",
                            value: location ?? "To be announced", accent: accent)
                EvdMetaTile(icon: .users, label: "Going",
                            value: going == 1 ? "1 person" : "\(going) people", accent: accent)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            // Native calendar write needs an EventKit entitlement — visual for now.
            Button {} label: { EvdActionLabel(icon: .calendarDays, text: "Add to calendar") }
                .buttonStyle(.plain)
            ShareLink(item: shareText) { EvdActionLabel(icon: .share2, text: "Share") }
                .buttonStyle(.plain)
        }
    }
}

private struct EvdMetaTile: View {
    let icon: Lucide
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.12))
                .frame(width: 32, height: 32)
                .overlay(Icon(icon, size: 15, color: accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.inter(9, .bold)).kerning(1.3)
                    .foregroundStyle(EvD.tertiary)
                Text(value)
                    .font(.inter(11, .semibold))
                    .foregroundStyle(EvD.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EvD.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color(hex: 0x0A2540, alpha: 0.06), lineWidth: 1))
    }
}

private struct EvdActionLabel: View {
    let icon: Lucide
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Icon(icon, size: 14, color: EvD.gold)
            Text(text).font(.inter(12, .bold)).foregroundStyle(EvD.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(EvD.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(EvD.borderMid, lineWidth: 1))
    }
}

// MARK: - About this gathering.

private struct EvdAboutCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EvdOverline("About this gathering")
            Text(text)
                .font(.nCardBody)
                .foregroundStyle(EvD.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .evdCard()
    }
}

// MARK: - Who's going — horizontal avatar rail + count.

private struct EvdRosterCard: View {
    let attendees: [EventAttendee]
    let going: Int

    private var shown: [EventAttendee] { Array(attendees.prefix(8)) }
    private var extra: Int { max(0, going - shown.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                EvdOverline("Who's going")
                Spacer(minLength: 0)
                Text(going == 1 ? "1 going" : "\(going) going")
                    .font(.inter(11, .bold)).foregroundStyle(EvD.ink)
            }
            if shown.isEmpty {
                Text("Be the first to RSVP.")
                    .font(.nCardBody).foregroundStyle(EvD.secondary)
            } else {
                rail
            }
        }
        .evdCard()
    }

    /// Bleeds to the card edges (Figma -mx-4 px-4) and scrolls horizontally.
    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(shown) { a in
                    VStack(spacing: 6) {
                        EvdRosterAvatar(attendee: a)
                        Text(firstName(a.fullName))
                            .font(.inter(10, .semibold)).foregroundStyle(EvD.body)
                            .lineLimit(1)
                    }
                    .frame(width: 52)
                }
                if extra > 0 { extraTile }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    private var extraTile: some View {
        VStack(spacing: 6) {
            Circle().fill(EvD.tile)
                .frame(width: 46, height: 46)
                .overlay(Circle().stroke(Color(hex: 0x0A2540, alpha: 0.12), lineWidth: 1))
                .overlay(Text("+\(extra)").font(.inter(12, .bold)).foregroundStyle(EvD.ink))
            Text("more").font(.inter(10, .semibold)).foregroundStyle(EvD.tertiary)
        }
        .frame(width: 52)
    }

    private func firstName(_ full: String) -> String {
        full.split(separator: " ").first.map(String.init) ?? full
    }
}

/// 46pt roster avatar — real photo when present, otherwise initials on the
/// member's deterministic gradient disc (Figma colorFor palette).
private struct EvdRosterAvatar: View {
    let attendee: EventAttendee

    private var accent: Color { EvD.avatarAccent(attendee.fullName) }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [accent, accent.opacity(0.71)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            if let s = attendee.avatarUrl, let url = URL(string: s) {
                CachedAsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() }
                    else { initials }
                }
            } else {
                initials
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(Circle())
        .shadow(color: accent.opacity(0.4), radius: 4, x: 0, y: 4)
    }

    private var initials: some View {
        Text(Avatar.initials(attendee.fullName))
            .font(.inter(14, .bold)).foregroundStyle(.white)
    }
}

// MARK: - RSVP — going / maybe / can't selector.

private struct EvdRsvpCard: View {
    @ObservedObject var vm: EventDetailViewModel

    private var mine: String? { vm.myRsvpOverride ?? vm.detail?.myRsvp }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EvdOverline("Will you be there?")
            HStack(spacing: 6) {
                option("Going", "going", tint: EvD.going)
                option("Maybe", "maybe", tint: EvD.maybe)
                option("Can't", "declined", tint: EvD.declined)
            }
            .padding(.top, 12)
            if mine == "going" {
                HStack(spacing: 6) {
                    Icon(.check, size: 13, color: EvD.goingText)
                    Text("Saved · we'll remind you the day before.")
                        .font(.inter(11, .semibold)).foregroundStyle(EvD.goingText)
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .evdCard()
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: mine)
    }

    private func option(_ label: String, _ status: String, tint: Color) -> some View {
        let on = mine == status
        return Button {
            guard !on else { return }
            Haptics.action()
            Task { await vm.setRsvp(status) }
        } label: {
            Text(label)
                .font(.inter(12, .bold))
                .foregroundStyle(on ? .white : EvD.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(on ? tint : .clear,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(on ? .clear : EvD.borderMid, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .disabled(vm.rsvpBusy)
        .opacity(vm.rsvpBusy ? 0.7 : 1)
    }
}

// MARK: - Who's coming — buzz header + working hype composer + real post feed.
// Wired to GET/POST /events/{id}/posts and /events/{id}/posts/{postId}/react.
// The make's image/camera pickers are not built: the posts contract carries an
// image_url, but the app has no member image-upload path yet, so those two
// buttons are omitted rather than shipped inert (images from other surfaces
// still render in the feed).

private struct EvdBuzzCard: View {
    @ObservedObject var vm: EventDetailViewModel
    var onComposerFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            EvdComposer(draft: $vm.postDraft, posting: vm.posting,
                        onPost: { Task { await vm.submitPost() } },
                        onFocus: onComposerFocus)
            if vm.posts.isEmpty {
                Text("Be the first to share a moment.")
                    .font(.nCardBody).foregroundStyle(EvD.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.posts) { p in
                        EvdBuzzPostRow(post: p) { kind in
                            Task { await vm.toggleReaction(p, kind: kind) }
                        }
                    }
                }
            }
        }
        .evdCard()
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Icon(.users, size: 12, color: EvD.overline)
                EvdOverline("Who's coming")
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                EvdPulseDot(size: 6)
                Text(vm.posts.isEmpty ? "Buzzing" : "Buzzing · \(vm.posts.count)")
                    .font(.inter(10, .bold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(LinearGradient(colors: [EvD.going, EvD.goingDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule())
            .shadow(color: EvD.going.opacity(0.35), radius: 5, x: 0, y: 3)
        }
    }
}

private struct EvdComposer: View {
    @Binding var draft: String
    let posting: Bool
    var onPost: () -> Void
    var onFocus: () -> Void
    @FocusState private var focused: Bool

    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                youDisc
                TextField("", text: $draft,
                          prompt: Text("Hype the room — say you're coming 🔥")
                            .foregroundColor(EvD.placeholder),
                          axis: .vertical)
                    .font(.inter(13)).foregroundStyle(EvD.ink)
                    .lineLimit(1...4)
                    .focused($focused)
                    .padding(.top, 9)
            }
            HStack(spacing: 6) {
                // Real, local: drops a 🔥 into the draft.
                Button {
                    Haptics.tap()
                    draft += draft.isEmpty ? "🔥" : " 🔥"
                } label: {
                    iconDisc(.flame, color: EvD.gold)
                }
                .buttonStyle(.pressable)
                Spacer(minLength: 0)
                postPill
            }
        }
        .padding(10)
        .background(LinearGradient(colors: [EvD.composerTop, EvD.tile],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(EvD.gold.opacity(0.28), lineWidth: 1))
        .shadow(color: EvD.navyBase.opacity(0.10), radius: 8, x: 0, y: 5)
        .onChange(of: focused) { _, f in if f { onFocus() } }
    }

    private var youDisc: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x163655)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 36, height: 36)
            .overlay(Text("You").font(.inter(10, .bold)).foregroundStyle(.white))
            .shadow(color: EvD.navyBase.opacity(0.3), radius: 5, x: 0, y: 3)
    }

    private func iconDisc(_ icon: Lucide, color: Color) -> some View {
        Circle().fill(.white)
            .frame(width: 36, height: 36)
            .overlay(Circle().stroke(Color(hex: 0x0A2540, alpha: 0.08), lineWidth: 1))
            .overlay(Icon(icon, size: 17, color: color))
    }

    private var postPill: some View {
        Button {
            Haptics.action()
            focused = false
            onPost()
        } label: {
            HStack(spacing: 6) {
                Text("Post").font(.inter(12, .bold)).foregroundStyle(EvD.ink)
                Icon(.send, size: 15, color: EvD.ink)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(LinearGradient(colors: [EvD.gold, EvD.goldDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule())
            .shadow(color: EvD.gold.opacity(0.35), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.pressable)
        .disabled(!hasDraft || posting)
        .opacity(!hasDraft || posting ? 0.55 : 1)
        .animation(.easeOut(duration: 0.18), value: hasDraft)
    }
}

/// One buzz post — author disc, name (+ Going tag), relative time, caption,
/// optional image, and the 🎉/❤️ single-reaction chips.
private struct EvdBuzzPostRow: View {
    let post: EventPost
    var onReact: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            EvdBuzzAvatar(name: post.authorName, url: post.authorAvatar)
            VStack(alignment: .leading, spacing: 4) {
                titleLine
                if let body = post.body, !body.isEmpty {
                    Text(body)
                        .font(.nCardBody).foregroundStyle(EvD.body)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                postImage
                reactions
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(EvD.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color(hex: 0x0A2540, alpha: 0.06), lineWidth: 1))
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(post.mine ? "You" : post.authorName)
                .font(.inter(12, .bold)).foregroundStyle(EvD.ink).lineLimit(1)
            if post.rsvpStatus == "going" {
                Text("GOING")
                    .font(.inter(8, .bold)).kerning(1)
                    .foregroundStyle(EvD.goingText)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(EvD.going.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 0)
            Text(EvdBuzzPostRow.relTime(post.createdAt))
                .font(.nCardMeta).foregroundStyle(EvD.tertiary)
        }
    }

    /// Natural-aspect thumb (height capped ~280), tap → full-screen lightbox.
    @ViewBuilder private var postImage: some View {
        if let s = post.imageUrl, let url = URL(string: s) {
            NaturalImageThumb(url: url, maxWidth: .infinity, maxHeight: 280)
        }
    }

    private var reactions: some View {
        HStack(spacing: 6) {
            chip("🎉", post.cheerCount, on: post.myReaction == "cheer") { onReact("cheer") }
            chip("❤️", post.loveCount, on: post.myReaction == "love") { onReact("love") }
        }
        .padding(.top, 2)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: post.myReaction)
    }

    private func chip(_ emoji: String, _ count: Int, on: Bool, tap: @escaping () -> Void) -> some View {
        Button {
            Haptics.love()
            tap()
        } label: {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 12))
                Text("\(count)").font(.inter(10, .bold))
                    .foregroundStyle(on ? EvD.goldDeep : EvD.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(on ? EvD.gold.opacity(0.14) : Color.white, in: Capsule())
            .overlay(Capsule().stroke(on ? EvD.gold.opacity(0.45) : EvD.borderMid, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    static func relTime(_ iso: String) -> String {
        let d = Ev.date(iso)
        if Date().timeIntervalSince(d) < 60 { return "now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}

/// 32pt author disc — photo when present, otherwise initials on the
/// deterministic accent gradient (same palette as the roster rail).
private struct EvdBuzzAvatar: View {
    let name: String
    let url: String?

    private var accent: Color { EvD.avatarAccent(name) }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [accent, accent.opacity(0.71)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            if let s = url, let u = URL(string: s) {
                CachedAsyncImage(url: u) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() }
                    else { initials }
                }
            } else {
                initials
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private var initials: some View {
        Text(Avatar.initials(name)).font(.inter(10, .bold)).foregroundStyle(.white)
    }
}

// MARK: - Check in — the gold scan CTA for today's/live occurrences. Opens
// CheckInScannerView (AVFoundation QR → POST /events/{id}/attendance).

private struct EvdCheckInButton: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Icon(.qrCode, size: 16, color: EvD.ink)
                Text("Check in").font(.inter(13, .bold)).foregroundStyle(EvD.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(LinearGradient(colors: [EvD.gold, EvD.goldDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: EvD.gold.opacity(0.35), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Check-in notice — the dashed locked state for future scheduled events.

private struct EvdCheckInNotice: View {
    var body: some View {
        HStack(spacing: 8) {
            Icon(.lock, size: 14, color: EvD.gold)
            Text("Check-in opens when the event is live")
                .font(.inter(12.5, .semibold)).foregroundStyle(Color(hex: 0x6A7686))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(EvD.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color(hex: 0x0A2540, alpha: 0.18),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

// MARK: - Bits shared across sections.

/// Section overline — 10pt uppercase, 0.18em tracking, muted gold.
private struct EvdOverline: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.nCardKicker).kerning(1.4)
            .foregroundStyle(EvD.overline)
    }
}

private extension View {
    /// Figma card chrome — white, radius 22, p-4, hairline navy border; the meta
    /// card floats on one soft shadow, the rest sit flat.
    func evdCard(shadow: Bool = false) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(EvD.border, lineWidth: 1))
            .shadow(color: shadow ? EvD.navyBase.opacity(0.16) : .clear, radius: 12, x: 0, y: 7)
    }
}
