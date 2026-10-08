// "I paid another way" (PARTNERS_PROGRAMME §1 rule d; Giving Cycle 5) — the
// member tells the office about money given toward a pledge outside the app
// (cash at church, a bank transfer, a paybill the app never saw), and the
// office matches it. The form keeps the server's rules before it sends:
//   · the pledge's own currency — shillings whole, dollars with cents
//     (422 CURRENCY_MISMATCH otherwise);
//   · a real day: today, or within the last year on the church's (Nairobi)
//     calendar (422 INVALID_DATE);
//   · a note of at most 300 characters;
//   · told once — the same amount and day again, or a sixth still waiting,
//     is the server's 409 CONFLICT, and its words are shown as they are.
// Online only: a claim is a statement about money, and money is never queued
// (§5.6). Offline, the button says so instead of sending.
import SwiftUI

// MARK: - The rules (pure — pinned by GivingCycle5ClaimTests)

enum ClaimRules {
    /// A note is at most this long, trimmed — the server's bound.
    static let noteLimit = 300
    /// How far back a claim may go, in days. The server allows one more;
    /// the picker stays inside it.
    static let lookbackDays = 365

    /// The first and last day a claim may name, on the church's calendar.
    static func dayRange(today: String) -> ClosedRange<String> {
        addDays(today, -lookbackDays)...today
    }

    /// `day` (YYYY-MM-DD) moved by `n` days on the church's calendar.
    static func addDays(_ day: String, _ n: Int) -> String {
        let cal = GiveCalendar.calendar
        guard let y = Int(day.prefix(4)), let m = Int(day.dropFirst(5).prefix(2)), let d = Int(day.dropFirst(8).prefix(2)),
              let noon = cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12)),
              let moved = cal.date(byAdding: .day, value: n, to: noon) else { return day }
        return PledgeMath.churchDay(of: moved)
    }

    /// What stops the claim from going, in words — nil when it can.
    static func problem(amountText: String, currency: String, paidOn: String, note: String, today: String) -> String? {
        let t = amountText.trimmingCharacters(in: .whitespaces)
        if MoneyEntry.minor(t, currency: currency) == nil {
            if MoneyEntry.wholeUnits(currency) && (t.contains(".") || t.contains(",")) { return "Shillings only — no cents." }
            return "Enter the amount you paid."
        }
        guard PledgeMath.isDay(paidOn), dayRange(today: today).contains(paidOn) else {
            return "Choose the day you paid — today or within the last year."
        }
        if note.trimmingCharacters(in: .whitespacesAndNewlines).count > noteLimit {
            return "Keep the note to \(noteLimit) characters."
        }
        return nil
    }

    /// What is sent — nil while `problem` has something to say. Always the
    /// pledge's own currency; an empty note is left out.
    static func body(amountText: String, currency: String, paidOn: String, note: String, today: String) -> MemberAPI.PledgeClaimBody? {
        guard problem(amountText: amountText, currency: currency, paidOn: paidOn, note: note, today: today) == nil,
              let minor = MoneyEntry.minor(amountText, currency: currency) else { return nil }
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return MemberAPI.PledgeClaimBody(amountMinor: minor, currency: currency.uppercased(), paidOn: paidOn, note: n.isEmpty ? nil : n)
    }

    // The date picker works on this device's calendar; a claim names a day.
    // A day is shown as that day at noon here, and a picked date is read
    // back by its year, month and day here — so the day the member taps is
    // the day that is sent, whatever their time zone.

    /// A day (YYYY-MM-DD) as the picker shows it.
    static func pickerDate(_ day: String, calendar: Calendar = .current) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date()
    }

    /// The picked date as a day.
    static func day(ofPicker date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return PledgeMath.ymd(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// The picker's range: the first allowed day's start to the last's end.
    static func pickerRange(today: String, calendar: Calendar = .current) -> ClosedRange<Date> {
        let range = dayRange(today: today)
        let first = calendar.startOfDay(for: pickerDate(range.lowerBound, calendar: calendar))
        let lastNoon = pickerDate(range.upperBound, calendar: calendar)
        let last = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: lastNoon) ?? lastNoon
        return first...max(first, last)
    }
}

// MARK: - The words

enum ClaimCopy {
    /// Where a claim stands, as the member reads it.
    static func status(_ status: String) -> String {
        switch status.lowercased() {
        case "confirmed": return "Recorded — thank you"
        case "rejected": return "The office couldn't match it"
        default: return "The office is checking it"
        }
    }

    /// "KSh 3,000 · paid Sat 12 Sep" (with the year when it isn't this one).
    static func line(_ claim: PledgeClaim, today: String) -> String {
        let when = PledgeMath.isDay(claim.paidOn) ? " · paid \(PledgeMath.dayLabel(claim.paidOn, today: today))" : ""
        return "\(GiveMoney.format(claim.amountMinor, claim.currency))\(when)"
    }
}

// MARK: - The form

struct PledgeClaimSheet: View {
    let pledge: Pledge
    /// "KSh 2,000 is being checked by the office" — what is already told
    /// (final walk M1); nil when nothing waits.
    var checking: String? = nil
    /// Sends the claim: nil when the office has it (the sheet closes), else
    /// the words to show — the server's own for a refusal.
    let onSend: (MemberAPI.PledgeClaimBody) async -> String?

    @ObservedObject private var sync = SyncCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var day: Date
    @State private var note = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var amountFocused: Bool
    @FocusState private var noteFocused: Bool
    /// The calendar under the day's pill is open.
    @State private var choosingDay = false
    /// The sheet is as tall as what it holds (§8.1 rule 5: its lower
    /// quarter stood empty).
    @State private var contentHeight: CGFloat = 0

    /// The church's today, fixed while the sheet is open.
    private let today: String

    init(pledge: Pledge, checking: String? = nil, onSend: @escaping (MemberAPI.PledgeClaimBody) async -> String?) {
        self.pledge = pledge
        self.checking = checking ?? pledge.claimLine
        self.onSend = onSend
        let t = PledgeMath.today()
        today = t
        _day = State(initialValue: ClaimRules.pickerDate(t))
    }

    private var currency: String { pledge.currency.uppercased() }
    private var paidOn: String { ClaimRules.day(ofPicker: day) }
    private var problem: String? {
        ClaimRules.problem(amountText: amountText, currency: currency, paidOn: paidOn, note: note, today: today)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                HStack {
                    Text("I paid another way")
                        .font(.fraunces(18, .semibold)).kerning(-0.36).foregroundStyle(Nuru.navy)
                    Spacer()
                    Button { dismiss() } label: {
                        ZStack {
                            Circle().fill(Nuru.surface).frame(width: 32, height: 32)
                            Icon(.x, size: 14, color: Nuru.navy)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.top, Nuru.S.lg)

                Text("Tell the office about money you gave toward \u{201C}\(pledge.displayTitle)\u{201D} outside the app — cash, a bank transfer, a paybill. They'll match it and add it to your pledge.")
                    .font(.nCaption).foregroundStyle(Nuru.ink600)
                    .fixedSize(horizontal: false, vertical: true)

                // What the office is already checking, so the same money is
                // never told twice (final walk M1).
                if let claim = checking {
                    Text(claim + ".")
                        .font(.inter(12, .semibold)).foregroundStyle(Nuru.goldChipText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    label("AMOUNT · IN \(GiveMoney.currencyWords(currency).uppercased())")
                    HStack(spacing: 8) {
                        Text(MoneyEntry.prefix(currency)).font(.inter(14, .medium)).foregroundStyle(Color(hex: 0x74808F))
                        TextField(MoneyEntry.wholeUnits(currency) ? "e.g. 2000" : "e.g. 20.00", text: $amountText)
                            .keyboardType(MoneyEntry.wholeUnits(currency) ? .numberPad : .decimalPad)
                            .font(.inter(16, .semibold))
                            .focused($amountFocused)
                            .onChange(of: amountText) { _, v in
                                let clean = MoneyEntry.sanitize(v, currency: currency)
                                if clean != v { amountText = clean }
                            }
                    }
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(amountFocused ? Nuru.gold : Nuru.border, lineWidth: 1))
                    Text(MoneyEntry.wholeUnits(currency)
                         ? "In whole shillings, as you paid it."
                         : "In \(GiveMoney.currencyWords(currency)) — this pledge's currency.")
                        .font(.nCaption).foregroundStyle(Nuru.ink400)
                }

                VStack(alignment: .leading, spacing: 8) {
                    label("THE DAY YOU PAID")
                    // The day in the one date shape (§8.1 rule 8: "Wed 7 Oct",
                    // not the system's "7 Oct 2026") on a white pill (rule 6:
                    // not the system's grey capsule); a tap opens the calendar
                    // in place.
                    Button {
                        Haptics.tap()
                        amountFocused = false; noteFocused = false
                        withAnimation(.easeInOut(duration: 0.2)) { choosingDay.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Icon(.calendar, size: 14, color: Nuru.gold)
                            Text(PledgeMath.dayLabel(paidOn, today: today))
                                .font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                            Icon(choosingDay ? .chevronUp : .chevronDown, size: 14, color: Nuru.ink400)
                        }
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(choosingDay ? Nuru.gold : Nuru.border, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("The day you paid: \(PledgeMath.dayLabel(paidOn, today: today))")
                    .accessibilityHint(choosingDay ? "Closes the calendar" : "Opens a calendar")
                    if choosingDay {
                        DatePicker("The day you paid", selection: $day, in: ClaimRules.pickerRange(today: today), displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.graphical)
                            .tint(Nuru.gold)
                            .padding(8)
                            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                            .transition(.opacity)
                    }
                    Text("Today, or any day in the last year.")
                        .font(.nCaption).foregroundStyle(Nuru.ink400)
                }

                VStack(alignment: .leading, spacing: 8) {
                    label("A NOTE FOR THE OFFICE · OPTIONAL")
                    HStack(alignment: .top, spacing: 8) {
                        Icon(.penLine, size: 14, color: Nuru.gold).padding(.top, 3)
                        TextField("e.g. Cash at the 9am service", text: $note, axis: .vertical)
                            .font(.inter(14))
                            .lineLimit(2...5)
                            .focused($noteFocused)
                            .onChange(of: note) { _, v in
                                if v.count > ClaimRules.noteLimit { note = String(v.prefix(ClaimRules.noteLimit)) }
                            }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(noteFocused ? Nuru.gold : Nuru.border, lineWidth: 1))
                    Text("\(note.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(ClaimRules.noteLimit)")
                        .font(.inter(11)).monospacedDigit().foregroundStyle(Nuru.ink400)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if !sync.isOnline {
                    Text("You're offline. Telling the office needs a connection — nothing is saved to send later.")
                        .font(.inter(12, .semibold)).foregroundStyle(Nuru.urgentText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let error {
                    Text(error).font(.inter(12)).foregroundStyle(Nuru.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !amountText.isEmpty, let problem {
                    Text(problem).font(.inter(12)).foregroundStyle(Nuru.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GoldSheetButton(title: sending ? "Sending…" : "Tell the office", busy: sending,
                                disabled: problem != nil || !sync.isOnline) { send() }
                    .padding(.top, Nuru.S.sm)

                Text("Nothing is charged. It's added to your pledge once the office confirms it.")
                    .font(.nCaption).foregroundStyle(Nuru.ink400)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.bottom, Nuru.S.lg)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { contentHeight = g.size.height }
                    .onChange(of: g.size.height) { _, h in contentHeight = h }
            })
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Nuru.paper.ignoresSafeArea())
        // As tall as what it holds (rule 5), the drag handle above it.
        .presentationDetents([contentHeight > 0
                              ? .height(PSheetFit.height(content: contentHeight, chrome: 12, screen: UIScreen.main.bounds.height))
                              : .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Nuru.paper)   // opaque, not the system's glass (§8.1 rule 5)
        .onChange(of: amountText) { _, _ in error = nil }
        .onChange(of: day) { _, _ in error = nil; withAnimation(.easeInOut(duration: 0.2)) { choosingDay = false } }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
    }

    private func send() {
        guard sync.isOnline, !sending,
              let body = ClaimRules.body(amountText: amountText, currency: currency, paidOn: paidOn, note: note, today: today)
        else { return }
        Haptics.action()
        amountFocused = false
        noteFocused = false
        error = nil
        sending = true
        Task {
            let failure = await onSend(body)
            sending = false
            if let failure {
                Haptics.error()
                error = failure
            } else {
                Haptics.success()
                dismiss()
            }
        }
    }
}

// MARK: - One claim, as the pledge page lists it

struct PledgeClaimRow: View {
    let claim: PledgeClaim
    let today: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.14)).frame(width: 32, height: 32)
                Icon(icon, size: 14, color: tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ClaimCopy.line(claim, today: today))
                    .font(.inter(13, .semibold)).foregroundStyle(Nuru.navy).lineLimit(1)
                Text(ClaimCopy.status(claim.status))
                    .font(.inter(12, .semibold)).foregroundStyle(tint)
                if let note = claim.note {
                    Text(note).font(.inter(11)).foregroundStyle(Nuru.ink400).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var icon: Lucide {
        switch claim.status {
        case "confirmed": return .badgeCheck
        case "rejected": return .circleX
        default: return .clock
        }
    }

    private var tint: Color {
        switch claim.status {
        case "confirmed": return Nuru.successText
        case "rejected": return Nuru.ink600
        default: return Nuru.goldChipText
        }
    }
}
