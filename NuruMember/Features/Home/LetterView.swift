// The Sunday Letter — a weekly pastoral letter written from the member's
// ACTUAL week (lessons finished, reflections, answered prayers), composed
// server-side by the intelligence layer and presented as warm stationery:
// cream paper, serif voice, a bundled theme illustration, a designed
// scripture card, and the gold Nuru seal.
//
// v2: the letter widened from {body, scripture_ref} to a fully composed
// personal letter (title/salutation/theme/highlights/next_step/share_line —
// see MemberAPI+Letters.swift). Every section below degrades gracefully for
// a pre-v2 letter (all five columns null on the wire, defaulted client-side)
// so the app's very first letters still read exactly as intended.
import SwiftUI

struct LetterView: View {
    let letter: PastoralLetter
    var onRead: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showArchive = false
    // Arrival — one restrained reveal on open, staged in three quick beats
    // (hero → seal → paper). Unread letters get a touch more presence (a
    // gentle scale-in on the hero, "receiving something") than a revisit.
    @State private var heroIn = false
    @State private var sealIn = false
    @State private var paperIn = false

    private var weekLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: letter.weekOf) else { return letter.weekOf }
        let out = DateFormatter()
        out.dateFormat = "d MMMM yyyy"
        return out.string(from: d)
    }

    var body: some View {
        ZStack {
            // Deep navy backdrop lets the paper glow.
            LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x081020)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                    seal.padding(.bottom, -34).zIndex(1)
                    paper
                        .padding(.horizontal, 22)
                        .padding(.bottom, 30)
                        .opacity(paperIn || reduceMotion ? 1 : 0)
                        .offset(y: paperIn || reduceMotion ? 0 : 10)
                }
            }

            // Close
            VStack {
                HStack {
                    Spacer()
                    Button {
                        Haptics.tap(); dismiss()
                    } label: {
                        Icon(.x, size: 15, color: .white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.16), in: Circle())
                    }
                    .padding(.trailing, 18)
                }
                Spacer()
            }
            .padding(.top, 14)
        }
        .sheet(isPresented: $showArchive) { LetterArchiveView() }
        .onAppear {
            guard letter.isUnread else { return }
            Task { _ = try? await MemberAPI.markLetterRead(letter.letterId); onRead() }
        }
        .task { stageReveal() }
    }

    /// Stages the one-time open animation. Unread letters play the full
    /// "receiving something" beat (hero scales in from rest); a revisit
    /// (already read) just settles in gently — no re-performing the moment
    /// that belongs to first arrival only.
    private func stageReveal() {
        guard !reduceMotion else { heroIn = true; sealIn = true; paperIn = true; return }
        withAnimation(.easeOut(duration: 0.5)) { heroIn = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(0.18)) { sealIn = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) { paperIn = true }
    }

    /// Hero illustration with the title set over it — the letter's opening
    /// beat, bundled art (never a network image) resolved from `image_key`
    /// with a total, always-renders fallback (LetterTheme.resolve).
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LetterHero(imageKey: letter.imageKey, height: 240)
            VStack(alignment: .leading, spacing: 6) {
                Text("THE SUNDAY LETTER").font(.inter(10, .bold)).kerning(2.0)
                    .foregroundStyle(Color.white.opacity(0.65))
                Text(letter.title)
                    .font(.fraunces(24, .semibold))
                    .foregroundStyle(.white)
                    .nuruLineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .scaleEffect(letter.isUnread && !reduceMotion ? (heroIn ? 1 : 0.97) : 1)
        .opacity(heroIn || reduceMotion ? 1 : 0)
    }

    /// Gold wax seal with the Nuru mark, overlapping the paper's top edge.
    private var seal: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0xE8CA6C), Color(hex: 0xB6862F)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 68, height: 68)
                .shadow(color: Color(hex: 0xC9A227).opacity(0.5), radius: 12, y: 5)
            Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5).frame(width: 54, height: 54)
            Text("N").font(.fraunces(30, .semibold)).foregroundStyle(Color(hex: 0x1E2A1F))
        }
        .scaleEffect(sealIn || reduceMotion ? 1 : 0.6)
        .opacity(sealIn || reduceMotion ? 1 : 0)
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Week of \(weekLabel)").font(.inter(12)).foregroundStyle(Color(hex: 0x74808F))
                Text(letter.salutation)
                    .font(.fraunces(18, .medium))
                    .foregroundStyle(Color(hex: 0x2A3441))
            }
            .padding(.top, 44)

            if let ref = letter.scriptureRef { scriptureCard(ref) }

            Text(letter.body)
                .font(.fraunces(17, .regular))
                .foregroundStyle(Color(hex: 0x2A3441))
                .nuruLineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)

            if !letter.highlights.isEmpty { momentsSection }

            signature

            if let step = letter.nextStep { nextStepCTA(step) }

            if let line = letter.shareLine { shareLineCard(line) }

            archiveLink
        }
        .padding(.horizontal, 24).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0xFFFDF6), Color(hex: 0xF8F3E6)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color(hex: 0xC9A227).opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }

    /// Scripture as a designed card — a kicker, the reference set in the
    /// serif voice, and a book glyph — never a bare inline reference.
    private func scriptureCard(_ ref: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(.bookOpen, size: 16, color: Color(hex: 0xA8861C))
            VStack(alignment: .leading, spacing: 2) {
                Text("SCRIPTURE").font(.inter(9, .bold)).kerning(1.8).foregroundStyle(Color(hex: 0xA8861C))
                Text(ref).font(.fraunces(16, .semibold)).foregroundStyle(Color(hex: 0x5B4712))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(hex: 0xFDF5E5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(hex: 0xF2E2BD), lineWidth: 1))
    }

    /// "This week" — 2-3 true, concrete observations, a quiet list (never a
    /// streak, never a count, never anything that could read as pressure).
    /// Omitted entirely when there's nothing true to say (an honest quiet
    /// week never gets a manufactured entry here).
    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THIS WEEK").font(.inter(10, .bold)).kerning(1.8).foregroundStyle(Color(hex: 0xA8861C))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(letter.highlights, id: \.self) { moment in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(Color(hex: 0xC9A227)).frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(moment)
                            .font(.inter(13))
                            .foregroundStyle(Color(hex: 0x4A5567))
                            .nuruLineSpacing(4)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var signature: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("With grace,").font(.fraunces(14, .regular)).italic()
                .foregroundStyle(Color(hex: 0x6B7686))
            Text("Nuru Place").font(.fraunces(16, .semibold))
                .foregroundStyle(Color(hex: 0x2A3441))
        }
    }

    /// The letter's close: ONE clear next action, never a menu. Server-
    /// computed (never AI-invented — see LetterNextStep), so the deep link
    /// always resolves to something that actually exists. Omitted entirely
    /// when there's nothing left to point at.
    private func nextStepCTA(_ step: LetterNextStep) -> some View {
        Button {
            Haptics.action()
            navigate(step)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Text(step.label)
                    .font(.inter(14, .bold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Icon(.arrowRight, size: 15, color: .white)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Nuru.primaryButton, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    /// Same deep-link vocabulary HomeView's `heroCard` already routes
    /// `NextAction` on: "module" + a `moduleId` opens that exact lesson;
    /// anything else lands generically on the Pathway tab.
    private func navigate(_ step: LetterNextStep) {
        if step.route == "module", let id = step.params?.moduleId, !id.isEmpty {
            tabs.openPathway(.module(id))
        } else {
            tabs.selected = .pathway
        }
    }

    /// A light share affordance for the ONE shareable line — not the whole
    /// letter, which stays personal. Omitted entirely when the server sent
    /// nothing worth sharing.
    private func shareLineCard(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(.quote, size: 14, color: Color(hex: 0xA8861C))
            Text(line)
                .font(.fraunces(13, .medium)).italic()
                .foregroundStyle(Color(hex: 0x5B4712))
                .nuruLineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            ShareLink(item: line) {
                Icon(.share2, size: 14, color: Color(hex: 0x8A6B1F))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: 0xFDF5E5), in: Circle())
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0xF2E2BD), lineWidth: 1))
    }

    private var archiveLink: some View {
        HStack {
            Spacer()
            Button {
                Haptics.tap()
                showArchive = true
            } label: {
                HStack(spacing: 6) {
                    Text("Past letters").font(.inter(12, .bold)).foregroundStyle(Color(hex: 0x8A6B1F))
                    Icon(.chevronRight, size: 12, color: Color(hex: 0x8A6B1F))
                }
            }
        }
        .padding(.top, 2)
    }
}
