// The new-pledge flow (PARTNERS_PROGRAMME §2.5) — a full-screen stepper:
// shape → amount → "what is this pledge for?" → due → "charge me
// automatically" → review → create. One decision per screen, and the review
// step repeats every choice in plain words before anything is posted,
// because a pledge is a promise and nobody should make one by accident.
//
// "What is this pledge for?" (pledge names contract) lays the server's
// `pledge_options` out ON the page as grouped, selectable cards — General
// partnership, funds, campaigns, approved department needs — plus a
// "Custom name" card that unfolds a name field. A pick sends the TARGET
// only (`fund` / `campaign_id` / `need_id`) and the server derives the name;
// a custom name sends `title` only and no target.
//
// Nothing here moves money. "Charge me automatically" asks the SERVER to
// create a schedule bound to the pledge (`auto_schedule`, §5) — the same
// server-charged path Give's Weekly/Monthly uses. A member who is not yet a
// partner is joined first (POST /giving/partners/join {}), then the pledge is
// made.
//
// GIVING CYCLE 5: automatic collection is a MONTHLY pledge's — on its due
// day, first on the first due day strictly after today (Nairobi), never
// today — and the flow says that date ("First collection: 5 October"). A
// total pledge has no such step (the server refuses it). The rails offered
// are the server's recurring ones (GET /giving/methods: M-Pesa today). A
// refusal (no number, a rail that is off, an amount out of range) comes
// before anything is written, so its words — and "nothing has changed" —
// are true; the same pledge sent twice is one (`reused`); and a pledge made
// whose collection could not be set up (`auto_schedule_error`) is handed
// back with the server's words so Partners can land on it and say why.
import SwiftUI

/// What the member has entered in the new-pledge flow, to compare with how it
/// opened (EXPERIENCE.md §7.2 #7, §7.1 rule 4: leaving never loses what you
/// entered without asking). The rail the flow moves off on its own
/// (`autoMethod`, when the server takes no recurring gift on it) is not an
/// entry, so it isn't here.
struct NewPledgeDraft: Equatable {
    var shape: String
    var amount: Int
    var customAmount: String
    var selectedOptionId: String?
    var useCustom: Bool
    var customName: String
    var dueDay: Int
    var dueOn: Date
    var autoCharge: Bool

    /// ✕ asks first ("Leave this pledge?") once anything has been chosen —
    /// past step 1, or step 1 changed. On step 1 as it opened, it closes at once.
    static func asksBeforeLeaving(onFirstStep: Bool, draft: NewPledgeDraft, opening: NewPledgeDraft) -> Bool {
        !(onFirstStep && draft == opening)
    }
}

struct NewPledgeFlow: View {
    let isMember: Bool
    /// What a pledge may be for — GET /giving/partnership `pledge_options`
    /// (General · funds · campaigns · department needs, in the server's order).
    var pledgeOptions: [PledgeOption] = []
    /// Servers that predate `pledge_options` send only campaigns; the picker
    /// then builds the same list from the five funds + these.
    let campaigns: [PledgeCampaignOption]
    /// The pledge the server made (or found: the same one a moment ago), and
    /// why its automatic collection could not be set up, when it could not.
    let onCreated: (_ pledge: Pledge, _ autoScheduleError: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable { case shape, amount, target, due, schedule, review }

    @State private var step: Step = .shape
    @State private var shape = "monthly"          // monthly | total
    @State private var amount = 2000              // KSh (major units)
    @State private var customAmount = ""
    /// The picked option's id; nil → the default, General partnership.
    @State private var selectedOptionId: String?
    /// "Custom name…" — a name of the member's own, and no target.
    @State private var useCustom = false
    @State private var customName = ""
    @State private var dueDay = min(28, max(1, Calendar.current.component(.day, from: Date())))
    @State private var dueOn = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var autoCharge = false
    @State private var autoMethod = "mpesa"       // mpesa | airtel
    /// GET /giving/methods — which rails take a recurring gift here. Nil
    /// until it answers (M-Pesa alone meanwhile, and if it never does).
    @State private var methods: GivingMethods?
    @State private var submitting = false
    @State private var error: String?
    @FocusState private var amountFocused: Bool
    @FocusState private var nameFocused: Bool
    /// How the flow opened — the draft ✕ compares against (§7.2 #7).
    @State private var opening: NewPledgeDraft?
    /// "Leave this pledge?" is up.
    @State private var askingToLeave = false

    private var draft: NewPledgeDraft {
        NewPledgeDraft(shape: shape, amount: amount, customAmount: customAmount, selectedOptionId: selectedOptionId,
                       useCustom: useCustom, customName: customName, dueDay: dueDay, dueOn: dueOn, autoCharge: autoCharge)
    }

    /// ✕: at once on step 1 as it opened; otherwise ask first — a promise
    /// half made is never thrown away silently (it used to be, from step 5).
    private func close() {
        if NewPledgeDraft.asksBeforeLeaving(onFirstStep: step == .shape, draft: draft, opening: opening ?? draft) {
            askingToLeave = true
        } else {
            dismiss()
        }
    }

    private static let presets = [500, 1000, 2000, 5000, 10_000, 20_000]
    /// The five funds Give offers, by code — the same codes the server keys
    /// on, with the Give tab's exact tile palette (GivingView `funds`) so a
    /// fund's card here looks like its tile there. Codes + labels are also the
    /// fallback list, for a server that sends no `pledge_options`.
    private struct FundLook { let code, label, tagline: String; let icon: Lucide; let tint, fg: UInt32 }
    private static let funds: [FundLook] = [
        FundLook(code: "tithe",        label: "Tithe",        tagline: "A faithful portion",  icon: .percent,   tint: Nuru.tileTint, fg: Nuru.tileIcon),
        FundLook(code: "offering",     label: "Offering",     tagline: "Freewill worship",    icon: .handHeart, tint: Nuru.tileTint, fg: Nuru.tileIcon),
        FundLook(code: "gift",         label: "Gift",         tagline: "A special gift",      icon: .gift,      tint: Nuru.tileTint, fg: Nuru.tileIcon),
        FundLook(code: "mission",      label: "Mission",      tagline: "Beyond our walls",    icon: .globe,     tint: Nuru.tileTint, fg: Nuru.tileIcon),
        FundLook(code: "discipleship", label: "Discipleship", tagline: "Growing the Pathway", icon: .bookOpen,  tint: Nuru.tileTint, fg: Nuru.tileIcon),
    ]
    /// A custom name is 2–60 characters (the contract's bounds).
    private static let customLimit = 2...60

    private var monthly: Bool { shape == "monthly" }

    /// The steps this pledge walks. A total pledge has no "collect it
    /// automatically?" — automatic collection is a monthly pledge's.
    private var steps: [Step] { monthly ? Step.allCases : Step.allCases.filter { $0 != .schedule } }

    /// The rails a pledge's automatic collection may run on: those the
    /// server says take a recurring gift (M-Pesa today), of the two a
    /// pledge's collection accepts (`auto_schedule.method`: mpesa | airtel).
    private var autoRails: [GivingMethod] {
        let m = methods ?? .fallback()
        return m.methods.filter { ["mpesa", "airtel"].contains($0.key) && m.allowsRecurring($0.key) }
    }

    private func railName(_ key: String) -> String {
        let label = autoRails.first { $0.key == key }?.label ?? ""
        return label.isEmpty ? givingMethodName(key) : label
    }

    /// The first automatic collection, as the server will set it: the first
    /// due day strictly after today on the church's calendar — never today.
    /// "5 October" ("5 January 2027" in another year).
    private var firstCollection: String {
        let today = PledgeMath.today()
        return PledgeMath.dayLabel(PledgeMath.firstDueAfter(today, day: dueDay), today: today)
    }

    /// The picker's rows: the server's, else General + the five funds + campaigns.
    private var options: [PledgeOption] {
        if !pledgeOptions.isEmpty { return pledgeOptions }
        var out = [PledgeOption(key: "general", title: "General partnership", kind: "general")]
        out += Self.funds.map { PledgeOption(key: "fund:\($0.code)", title: $0.label, kind: "fund", fund: $0.code) }
        out += campaigns.map { PledgeOption(key: "campaign:\($0.campaignId)", title: $0.title, kind: "campaign", campaignId: $0.campaignId) }
        return out
    }
    private var defaultOption: PledgeOption? { options.first { $0.kind == "general" } ?? options.first }
    private var selectedOption: PledgeOption? { options.first { $0.id == selectedOptionId } ?? defaultOption }
    private var trimmedCustom: String { customName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var customValid: Bool { Self.customLimit.contains(trimmedCustom.count) }
    /// What the review step shows and the pledge will be called.
    private var chosenName: String { useCustom ? trimmedCustom : (selectedOption?.title ?? "General partnership") }

    private var canContinue: Bool {
        switch step {
        case .amount: return amount > 0
        case .target: return useCustom ? customValid : selectedOption != nil
        case .due: return monthly ? (1...28).contains(dueDay) : dueOn > Date()
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    stepTitle
                    switch step {
                    case .shape: shapeStep
                    case .amount: amountStep
                    case .target: targetStep
                    case .due: dueStep
                    case .schedule: scheduleStep
                    case .review: reviewStep
                    }
                    if let error {
                        Text(error).font(.inter(12)).foregroundStyle(Nuru.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.md)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Nuru.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .animation(.easeInOut(duration: 0.2), value: step)
        .onAppear { if opening == nil { opening = draft } }
        .task { await loadMethods() }
        // An alert, not a confirmation dialog: both answers stay on screen
        // (a dialog's cancel can fold away into "tap outside").
        .alert("Leave this pledge?", isPresented: $askingToLeave) {
            Button("Keep editing", role: .cancel) {}
            Button("Leave", role: .destructive) { dismiss() }
        } message: {
            Text("What you entered won't be kept.")
        }
    }

    /// The server's rails, once. A failed read keeps M-Pesa alone — the
    /// server still refuses a rail it cannot collect on, before anything is
    /// written. With none that can, automatic collection is switched off.
    private func loadMethods() async {
        guard methods == nil else { return }
        methods = (try? await MemberAPI.givingMethods()) ?? .fallback()
        if let first = autoRails.first {
            if !autoRails.contains(where: { $0.key == autoMethod }) { autoMethod = first.key }
        } else {
            autoCharge = false
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Button { Haptics.tap(); close() } label: {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
                        Icon(.x, size: 18, color: Nuru.navy)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
                Text("Step \((steps.firstIndex(of: step) ?? 0) + 1) of \(steps.count)")
                    .font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x74808F))
            }
            HStack(spacing: 5) {
                ForEach(steps, id: \.rawValue) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? Nuru.gold : Nuru.navy.opacity(0.10))
                        .frame(height: 4)
                }
            }
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("NEW PLEDGE").font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0x9A7A2A))
                Text("A promise, in your words").font(.fraunces(26, .semibold)).foregroundStyle(Nuru.navy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 60)
        .padding(.bottom, Nuru.S.base)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
        .ignoresSafeArea(edges: .top)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if step != .shape {
                Button { Haptics.tap(); back() } label: {
                    HStack(spacing: 6) {
                        Icon(.arrowLeft, size: 14, color: Nuru.navy)
                        Text("Back").font(.inter(14, .semibold))
                    }
                    .foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 18).frame(height: 48)
                    .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .disabled(submitting)
            }
            Button {
                Haptics.action()
                if step == .review { Task { await create() } } else { next() }
            } label: {
                HStack(spacing: 6) {
                    if submitting {
                        ProgressView().tint(Nuru.navy).scaleEffect(0.8)
                        Text("Creating…")
                    } else if step == .review {
                        Text("Create pledge")
                        Icon(.check, size: 14, color: Nuru.navy)
                    } else {
                        Text("Continue")
                        Icon(.arrowRight, size: 14, color: Nuru.navy)
                    }
                }
                .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(
                    LinearGradient(colors: [Nuru.gold, Color(hex: 0xB6862F)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Nuru.gold.opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.pressable)
            .disabled(submitting || !canContinue)
            .opacity(canContinue ? 1 : 0.6)
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.md)
        .padding(.bottom, Nuru.S.md)
        .background(Nuru.paper.opacity(0.96))
        .overlay(alignment: .top) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    private func next() {
        error = nil
        amountFocused = false
        nameFocused = false
        if let i = steps.firstIndex(of: step), i + 1 < steps.count { step = steps[i + 1] }
    }
    private func back() {
        error = nil
        amountFocused = false
        nameFocused = false
        if let i = steps.firstIndex(of: step), i > 0 { step = steps[i - 1] }
    }

    // MARK: Steps

    private var stepTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.nuruDisplay(22)).foregroundStyle(Nuru.ink)
            Text(subtitle).font(.nBody).foregroundStyle(Nuru.ink600)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        switch step {
        case .shape: return "What shape is the promise?"
        case .amount: return monthly ? "How much each month?" : "How much in total?"
        case .target: return "What is this pledge for?"
        case .due: return monthly ? "Which day of the month?" : "By when?"
        case .schedule: return "Collect it automatically?"
        case .review: return "Here is your pledge"
        }
    }
    private var subtitle: String {
        switch step {
        case .shape: return "Monthly and open-ended, or a total you will reach by a date — in any instalments."
        case .amount: return "Choose an amount, or enter your own. You can change it later."
        case .target: return "Pick what your promise supports, or name it yourself."
        case .due: return monthly ? "We'll remind you a few days before, if you'd like." : "The date you would like the total reached by."
        case .schedule: return "If you'd rather not remember, we can collect it for you each month — on your due day, by mobile money. Nothing is collected today."
        case .review: return "Read it once more. Nothing is charged by creating it."
        }
    }

    private var shapeStep: some View {
        VStack(spacing: 10) {
            choiceCard(on: monthly, icon: .calendarClock, title: "Monthly",
                       body: "An amount every month, for as long as you choose.") { shape = "monthly" }
            choiceCard(on: !monthly, icon: .target, title: "A total, by a date",
                       body: "A goal you reach in instalments of any size.") { shape = "total"; autoCharge = false }
        }
    }

    private var amountStep: some View {
        VStack(alignment: .leading, spacing: Nuru.S.base) {
            VStack(spacing: 4) {
                Text("AMOUNT").font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0x74808F))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("KSh").font(.inter(14, .medium)).foregroundStyle(Color(hex: 0x74808F))
                    Text(amount.formatted(.number.grouping(.automatic)))
                        .font(.fraunces(28, .semibold)).kerning(-1.2).foregroundStyle(Nuru.navy)
                        .contentTransition(.numericText(value: Double(amount)))
                }
                Text(monthly ? "each month" : "in total").font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
            }
            .frame(maxWidth: .infinity)

            // Amount choices are pills, as on Give (§8.1 rule 6, §8.2 #12) —
            // they were square tiles. Six of them, three across.
            NuruAmountPills(amounts: Self.presets, selected: customAmount.isEmpty ? amount : nil, columns: 3,
                            label: { $0.formatted(.number.grouping(.automatic)) }) { v in
                customAmount = ""
                amountFocused = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { amount = v }
            }

            HStack(spacing: 8) {
                Icon(.pencil, size: 14, color: Nuru.gold)
                TextField("Or enter your own amount", text: $customAmount)
                    .keyboardType(.numberPad)
                    .font(.inter(14))
                    .focused($amountFocused)
                    .onChange(of: customAmount) { _, v in
                        let digits = v.filter(\.isNumber)
                        if digits != v { customAmount = digits }
                        if let n = Int(digits), n > 0 { amount = n }
                    }
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(amountFocused ? Nuru.gold : Nuru.border, lineWidth: 1))
        }
        .padding(Nuru.S.screen)
        .background(Nuru.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: "What is this pledge for?" — every option ON the page, grouped by
    // kind, as selectable cards (no popup), + a "name it yourself" card

    private struct OptionGroup: Identifiable {
        let kind: String
        let label: String
        let rows: [PledgeOption]
        var id: String { kind }
    }

    /// The groups in the contract's order. A kind this build doesn't know
    /// lands under "Other" rather than vanishing.
    private var optionGroups: [OptionGroup] {
        let known: [(kind: String, label: String)] = [
            ("general", "GENERAL"), ("fund", "FUNDS"), ("campaign", "CAMPAIGNS"), ("need", "DEPARTMENT NEEDS"),
        ]
        var groups = known.map { pair in OptionGroup(kind: pair.kind, label: pair.label, rows: options.filter { $0.kind == pair.kind }) }
        let other = options.filter { o in !known.contains { $0.kind == o.kind } }
        if !other.isEmpty { groups.append(OptionGroup(kind: "other", label: "OTHER", rows: other)) }
        return groups.filter { !$0.rows.isEmpty }
    }

    /// How an option's card reads: its glyph, the tile behind it, and a
    /// one-line cue about what the choice means. A fund borrows the Give
    /// tab's tile exactly; an unknown fund code gets a neutral gold tile.
    private struct OptionLook { let icon: Lucide; let tint: Color; let fg: Color; let subtitle: String }
    private func look(for o: PledgeOption) -> OptionLook {
        switch o.kind {
        case "general":
            return OptionLook(icon: .heartHandshake, tint: Color(hex: 0xEEF1F5), fg: Nuru.navy, subtitle: "The church as a whole")
        case "fund":
            let code = (o.fund ?? "").lowercased()
            if let f = Self.funds.first(where: { $0.code == code }) {
                return OptionLook(icon: f.icon, tint: Color(hex: f.tint), fg: Color(hex: f.fg), subtitle: f.tagline)
            }
            return OptionLook(icon: .landmark, tint: Color(hex: Nuru.tileTint), fg: Color(hex: Nuru.tileIcon), subtitle: "A fund of the church")
        case "campaign":
            return OptionLook(icon: .megaphone, tint: Color(hex: Nuru.tileTint), fg: Color(hex: Nuru.tileIcon), subtitle: "Church campaign")
        case "need":
            return OptionLook(icon: .handHeart, tint: Color(hex: Nuru.tileTint), fg: Color(hex: Nuru.tileIcon), subtitle: "Department need")
        default:
            return OptionLook(icon: .target, tint: Color(hex: Nuru.tileTint), fg: Color(hex: Nuru.tileIcon), subtitle: "Another cause of the church")
        }
    }

    /// The selected card's cream wash (the Give tab's selected-tile tint).
    private static let selectedTint = Color(hex: 0xFFF9EC)

    private var targetStep: some View {
        VStack(alignment: .leading, spacing: Nuru.S.base) {
            ForEach(optionGroups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    eyebrow(group.label)
                    ForEach(group.rows) { o in optionCard(o) }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                eyebrow("NAME IT YOURSELF")
                customCard
            }
        }
        .animation(.easeInOut(duration: 0.2), value: useCustom)
        .animation(.easeInOut(duration: 0.2), value: selectedOptionId)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text).font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
    }

    /// One option as a full-width card. A tap selects it (and folds the
    /// custom field away, keeping whatever was typed); tapping the selected
    /// card again does nothing.
    private func optionCard(_ o: PledgeOption) -> some View {
        let on = !useCustom && selectedOption?.id == o.id
        let l = look(for: o)
        return Button {
            guard !on else { return }
            Haptics.selection()
            nameFocused = false
            useCustom = false
            selectedOptionId = o.id
        } label: {
            cardRow(on: on, icon: l.icon, tint: l.tint, fg: l.fg, title: o.title, subtitle: l.subtitle)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(on ? Self.selectedTint : Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? Nuru.gold : Nuru.border, lineWidth: on ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(o.title)
        .accessibilityValue(l.subtitle)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The "Custom name" card: a tap selects it and unfolds the name field
    /// inside the same card. The field sits OUTSIDE the button so its own
    /// taps still reach it; picking another card folds it away again.
    private var customCard: some View {
        let on = useCustom
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                guard !on else { return }
                Haptics.selection()
                useCustom = true
                nameFocused = true
            } label: {
                cardRow(on: on, icon: .penLine, tint: Nuru.gold.opacity(0.12), fg: Nuru.gold,
                        title: "Custom name", subtitle: "A promise in your own words")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Custom name")
            .accessibilityValue("A promise in your own words")
            .accessibilityAddTraits(on ? .isSelected : [])
            if on {
                customNameField.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(on ? Self.selectedTint : Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? Nuru.gold : Nuru.border, lineWidth: on ? 2 : 1))
    }

    /// The card's row: 40pt icon tile · title + one-line cue · check circle.
    private func cardRow(on: Bool, icon: Lucide, tint: Color, fg: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint).frame(width: 40, height: 40)
                Icon(icon, size: 18, color: fg)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.inter(15, .semibold)).foregroundStyle(Nuru.ink).lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle).font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472)).lineLimit(1)
            }
            Spacer(minLength: 8)
            ZStack {
                if on {
                    Circle().fill(Nuru.gold).frame(width: 22, height: 22)
                    Icon(.check, size: 14, color: Nuru.navy)
                } else {
                    Circle().stroke(Nuru.border, lineWidth: 1.5).frame(width: 22, height: 22)
                }
            }
        }
    }

    /// 2–60 characters, with a counter — the name goes on the pledge card
    /// and the statement; no target travels with it.
    private var customNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Icon(.penLine, size: 14, color: Nuru.gold)
                TextField("e.g. School fees for Grace", text: $customName)
                    .font(.inter(14))
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onChange(of: customName) { _, v in
                        let cap = Self.customLimit.upperBound
                        if v.count > cap { customName = String(v.prefix(cap)) }
                    }
                Text("\(trimmedCustom.count)/\(Self.customLimit.upperBound)")
                    .font(.inter(11)).monospacedDigit()
                    .foregroundStyle(customValid || trimmedCustom.isEmpty ? Nuru.ink400 : Nuru.danger)
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(nameFocused ? Nuru.gold : Nuru.border, lineWidth: 1))
            Text("2–60 characters. It goes on your pledge card and statement; the office directs the money where it is needed.")
                .font(.nCaption).foregroundStyle(Nuru.ink400)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dueStep: some View {
        Group {
            if monthly {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(1...28, id: \.self) { d in
                        let on = dueDay == d
                        Button {
                            Haptics.selection(); dueDay = d
                        } label: {
                            Text("\(d)").font(.inter(14, .semibold)).foregroundStyle(on ? .white : Nuru.navy)
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(on ? Nuru.navy : Nuru.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? .clear : Nuru.border, lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(Nuru.S.md)
                .background(Nuru.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            } else {
                DatePicker("Reach it by", selection: $dueOn,
                           in: (Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())...,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Nuru.gold)
                    .padding(Nuru.S.md)
                    .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
        }
    }

    /// A monthly pledge only (a total one skips this step).
    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: Nuru.S.base) {
            Toggle(isOn: $autoCharge) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Charge me automatically").font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                    Text("On the \(ordinal(dueDay)) of every month, by mobile money.")
                        .font(.nCaption).foregroundStyle(Nuru.ink600)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Nuru.gold)
            .disabled(autoRails.isEmpty)
            .padding(16)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))

            if autoRails.isEmpty {
                Text("Automatic collection isn't available right now. You'll pay each instalment yourself with \"Pay now\" on the pledge.")
                    .font(.nCaption).foregroundStyle(Nuru.ink400)
                    .fixedSize(horizontal: false, vertical: true)
            } else if autoCharge {
                // The day the member can hold us to — the server's own rule.
                HStack(spacing: 8) {
                    Icon(.calendarClock, size: 14, color: Nuru.gold)
                    Text("First collection: \(firstCollection)")
                        .font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                }
                .accessibilityElement(children: .combine)
                Text("BY").font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                HStack(spacing: 8) {
                    ForEach(autoRails) { rail in
                        methodChip(rail.key, railName(rail.key))
                    }
                }
                Text("Never today — then on the \(ordinal(dueDay)) of each month. You can stop it at any time from your recurring gifts.")
                    .font(.nCaption).foregroundStyle(Nuru.ink400)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("You'll pay each instalment yourself with \"Pay now\" on the pledge, and we'll remind you before it's due if you'd like.")
                    .font(.nCaption).foregroundStyle(Nuru.ink400)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: autoCharge)
    }

    private func methodChip(_ key: String, _ label: String) -> some View {
        let on = autoMethod == key
        return Button {
            Haptics.selection(); autoMethod = key
        } label: {
            HStack(spacing: 8) {
                // The rail's mark on the one tile look (§8.1 rule 1), not its brand hue.
                Text(key == "mpesa" ? "M" : "A").font(.inter(11, .bold)).foregroundStyle(Color(hex: Nuru.tileIcon))
                    .frame(width: 26, height: 26)
                    .background(Color(hex: Nuru.tileTint), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(label).font(.inter(13, .semibold)).foregroundStyle(on ? .white : Nuru.navy)
            }
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(on ? Nuru.navy : Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? .clear : Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewRow("Shape", monthly ? "Monthly" : "A total, by a date")
            reviewRow(monthly ? "Each month" : "Total", ksh(amount))
            reviewRow("For", chosenName)
            reviewRow(monthly ? "Due day" : "By", monthly ? "The \(ordinal(dueDay)) of each month" : longDate(dueOn))
            reviewRow("Collected", monthly && autoCharge ? "Automatically · \(railName(autoMethod))" : "By you, with Pay now")
            if monthly && autoCharge {
                reviewRow("First collection", firstCollection)
            }
            if !isMember {
                HStack(spacing: 8) {
                    Icon(.heartHandshake, size: 14, color: Nuru.gold)
                    Text("Creating this also joins you to the Partners programme.")
                        .font(.nCaption).foregroundStyle(Nuru.goldChipText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.gold.opacity(0.28), lineWidth: 1))
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.nBody).foregroundStyle(Nuru.ink600)
            Spacer(minLength: 12)
            Text(value).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }

    // MARK: Create

    private func create() async {
        guard amount > 0 else { return }
        if useCustom && !customValid {
            error = "A custom name is 2–60 characters."
            return
        }
        submitting = true
        defer { submitting = false }
        error = nil
        var body = MemberAPI.PledgeCreateBody(shape: shape, currency: "KES", idempotencyKey: GiveKey.fresh())
        if monthly {
            body.amountMinor = amount * 100
            body.dueDay = dueDay
        } else {
            body.targetMinor = amount * 100
            body.dueOn = ymd(dueOn)
        }
        if useCustom {
            // A name of the member's own: `title` only, no target — the
            // office directs the money.
            body.title = trimmedCustom
        } else if let o = selectedOption {
            // A pick: the TARGET only — the server derives the name, so no
            // `title` travels with it.
            switch o.kind {
            case "fund": body.fund = o.fund
            case "campaign": body.campaignId = o.campaignId
            case "need": body.needId = o.needId
            default: break    // general: no target
            }
        }
        // Monthly only: the server refuses automatic collection on a total
        // pledge, and collects a monthly one once a month on its due day.
        if monthly && autoCharge {
            body.autoSchedule = .init(method: autoMethod, frequency: "monthly")
        }
        do {
            if !isMember { try await MemberAPI.joinPartners() }
            // `reused`: the same pledge a moment ago, answered again — a
            // success like any other, never a second pledge.
            let made = try await MemberAPI.createPledge(body)
            Haptics.success()
            onCreated(made.pledge, made.autoScheduleError)
            dismiss()
        } catch {
            Haptics.error()
            if GiveRefusal.gotNoServerAnswer(error) {
                // No answer: it may have been made. Sending the same pledge
                // again finds that one rather than making a second.
                self.error = "We couldn't hear back from the church. Try again — if your pledge was made, it won't be made twice."
            } else {
                // A refusal comes before anything is written: the server's
                // words. Anything else (a 5xx, an unreadable answer) says
                // so in the one state language — never the raw text (§7.3).
                self.error = GiveRefusal.from(error).message
            }
        }
    }

    // MARK: Pieces

    private func choiceCard(on: Bool, icon: Lucide, title: String, body: String?, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection(); action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(on ? Nuru.gold : Nuru.gold.opacity(0.12)).frame(width: 40, height: 40)
                    Icon(icon, size: 18, color: on ? Nuru.navy : Nuru.gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                    if let body {
                        Text(body).font(.nCaption).foregroundStyle(Nuru.ink600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().stroke(on ? Nuru.gold : Nuru.border, lineWidth: on ? 6 : 1.5).frame(width: 20, height: 20)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? Nuru.gold.opacity(0.6) : Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    private func ymd(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
    private func longDate(_ d: Date) -> String {
        NuruDates.day(d)
    }
    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}

// MARK: - Edit name / amount / due day (PATCH /giving/pledges/{id})

/// A pledge's promise as its edit handles it (Giving Cycle 6): in the
/// pledge's OWN currency — shillings whole, dollars with cents — by the same
/// rules as Give (MoneyEntry, and Give's suggested amounts per currency). It
/// used to be shillings for every pledge: a dollar pledge read "KSh" and
/// could only be whole.
enum PledgeAmountEdit {
    /// The suggested amounts, in minor units: KSh 500 … 20,000, or Give's
    /// dollar ones (US$ 5 … 100).
    static func presets(_ currency: String) -> [Int] {
        MoneyEntry.wholeUnits(currency) ? [500, 1000, 2000, 5000, 10_000, 20_000].map { $0 * 100 } : UsdEntry.presetsCents
    }

    /// What the save sends for the promise: the new amount when it is one
    /// and differs from the pledge's, else nil (left as it is).
    static func changed(_ minor: Int, from pledge: Pledge) -> Int? {
        minor > 0 && minor != pledge.commitmentMinor ? minor : nil
    }
}

struct EditPledgeSheet: View {
    let pledge: Pledge
    /// Returns true when the server accepted the change (the sheet closes).
    /// `amountMinor` is the new promise in the pledge's own currency (nil =
    /// untouched). `title` is nil when the name is untouched, `.set` for a
    /// new custom name, `.clear` to drop it (the server falls back to its
    /// derived name).
    let onSave: (_ amountMinor: Int?, _ dueDay: Int?, _ title: MemberAPI.PledgePatchBody.TitlePatch?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    /// The promise, in minor units of the pledge's own currency.
    @State private var amountMinor: Int
    @State private var customAmount = ""
    @State private var dueDay: Int
    @State private var saving = false
    @FocusState private var amountFocused: Bool
    @FocusState private var nameFocused: Bool

    private static let nameLimit = 2...60

    init(pledge: Pledge, onSave: @escaping (_ amountMinor: Int?, _ dueDay: Int?, _ title: MemberAPI.PledgePatchBody.TitlePatch?) async -> Bool) {
        self.pledge = pledge
        self.onSave = onSave
        _name = State(initialValue: pledge.customTitle ?? pledge.displayTitle)
        _amountMinor = State(initialValue: pledge.commitmentMinor)
        _dueDay = State(initialValue: pledge.dueDay ?? 1)
    }

    private var currency: String { pledge.currency.uppercased() }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Empty is allowed (it clears a custom name); anything else is 2–60.
    private var nameValid: Bool { trimmedName.isEmpty || Self.nameLimit.contains(trimmedName.count) }
    /// nil = untouched · .set = a new custom name · .clear = back to the
    /// derived name. Clearing a name that was never custom is a no-op, so it
    /// is "untouched" rather than a pointless PATCH.
    private var titlePatch: MemberAPI.PledgePatchBody.TitlePatch? {
        if trimmedName == (pledge.customTitle ?? pledge.displayTitle) { return nil }
        if trimmedName.isEmpty { return pledge.customTitle == nil ? nil : .clear }
        return .set(trimmedName)
    }

    private var changed: Bool {
        PledgeAmountEdit.changed(amountMinor, from: pledge) != nil
            || (pledge.isMonthly && dueDay != (pledge.dueDay ?? 1))
            || titlePatch != nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                HStack {
                    Text("Edit pledge")
                        .font(.fraunces(18, .semibold)).kerning(-0.36).foregroundStyle(Nuru.navy)
                    Spacer()
                    Button { dismiss() } label: {
                        ZStack {
                            Circle().fill(Nuru.surface).frame(width: 32, height: 32)
                            Icon(.x, size: 14, color: Nuru.navy)
                        }
                    }.buttonStyle(.plain)
                }
                .padding(.top, Nuru.S.lg)

                VStack(alignment: .leading, spacing: 8) {
                    Text("NAME").font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                    HStack(spacing: 8) {
                        Icon(.penLine, size: 14, color: Nuru.gold)
                        TextField("Name this pledge", text: $name)
                            .font(.inter(14))
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onChange(of: name) { _, v in
                                let cap = Self.nameLimit.upperBound
                                if v.count > cap { name = String(v.prefix(cap)) }
                            }
                        Text("\(trimmedName.count)/\(Self.nameLimit.upperBound)")
                            .font(.inter(11)).monospacedDigit()
                            .foregroundStyle(nameValid ? Nuru.ink400 : Nuru.danger)
                    }
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(nameFocused ? Nuru.gold : Nuru.border, lineWidth: 1))
                    Text(pledge.customTitle == nil
                         ? "Named after what it's for. Give it a name of your own if you like — 2–60 characters."
                         : "2–60 characters. Clear it to go back to the name of what it's for.")
                        .font(.nCaption).foregroundStyle(Nuru.ink400)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 4) {
                    Text(pledge.isMonthly ? "EACH MONTH" : "TOTAL").font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0x74808F))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(MoneyEntry.prefix(currency)).font(.inter(14, .medium)).foregroundStyle(Color(hex: 0x74808F))
                        Text(MoneyEntry.display(amountMinor, currency: currency))
                            .font(.fraunces(28, .semibold)).kerning(-1.1).foregroundStyle(Nuru.navy)
                            .contentTransition(.numericText(value: Double(amountMinor)))
                    }
                }
                .frame(maxWidth: .infinity)

                // The same pills as the new-pledge step (§8.1 rule 6).
                NuruAmountPills(amounts: PledgeAmountEdit.presets(currency), selected: customAmount.isEmpty ? amountMinor : nil,
                                columns: 3, label: { ($0 / 100).formatted(.number.grouping(.automatic)) }) { v in
                    customAmount = ""; amountFocused = false
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { amountMinor = v }
                }

                HStack(spacing: 8) {
                    Icon(.pencil, size: 14, color: Nuru.gold)
                    TextField(MoneyEntry.wholeUnits(currency) ? "Or enter your own amount" : "Or enter your own amount, e.g. 20.00",
                              text: $customAmount)
                        .keyboardType(MoneyEntry.wholeUnits(currency) ? .numberPad : .decimalPad)
                        .font(.inter(14))
                        .focused($amountFocused)
                        .onChange(of: customAmount) { _, v in
                            // Give's rules, in the pledge's money: whole
                            // shillings, or dollars and cents.
                            let clean = MoneyEntry.sanitize(v, currency: currency)
                            if clean != v { customAmount = clean; return }
                            if let m = MoneyEntry.minor(clean, currency: currency) { amountMinor = m }
                        }
                }
                .padding(.horizontal, 14).frame(height: 44)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(amountFocused ? Nuru.gold : Nuru.border, lineWidth: 1))
                if !MoneyEntry.wholeUnits(currency) {
                    Text("This pledge is in \(GiveMoney.currencyWords(currency)).")
                        .font(.nCaption).foregroundStyle(Nuru.ink400)
                }

                if pledge.isMonthly {
                    Text("DUE DAY").font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(1...28, id: \.self) { d in
                            let on = dueDay == d
                            Button { Haptics.selection(); dueDay = d } label: {
                                Text("\(d)").font(.inter(13, .semibold)).foregroundStyle(on ? .white : Nuru.navy)
                                    .frame(maxWidth: .infinity).frame(height: 36)
                                    .background(on ? Nuru.navy : Nuru.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? .clear : Nuru.border, lineWidth: 1))
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }

                GoldSheetButton(title: saving ? "Saving…" : "Save changes", busy: saving, disabled: !changed || amountMinor <= 0 || !nameValid) {
                    Haptics.action()
                    nameFocused = false
                    amountFocused = false
                    Task {
                        saving = true
                        let ok = await onSave(PledgeAmountEdit.changed(amountMinor, from: pledge),
                                              pledge.isMonthly && dueDay != (pledge.dueDay ?? 1) ? dueDay : nil,
                                              titlePatch)
                        saving = false
                        if ok { dismiss() }
                    }
                }
                .padding(.top, Nuru.S.sm)
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.bottom, Nuru.S.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Nuru.paper.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
