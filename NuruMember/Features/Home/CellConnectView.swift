// "Ask to be connected" — finding a cell (owner, 2026-10-05; pathway docs/
// EXPERIENCE.md §9.2 #12). "Find your cell" opened Community, which has no way
// to find one, while 37 of 76 members in production have no cell. The member
// says where they live and when they're free; the request goes to their own
// pastor, in their own pastoral thread (POST /me/cell-connection, ed1525d).
//   - already in a cell (the GET says so, or the POST's 409): the cell page;
//   - asked already, on any phone: "Sent to your pastor on Mon 5 Oct — they'll
//     connect you · Open the conversation";
//   - a minor, or a church with no pastor to receive it: the server's own
//     words (422), with Go back;
//   - otherwise the short form → "Ask the church". A failed send keeps the
//     words typed and says why in §4's words; one client id per ask is kept
//     across retries, so a retry can't post twice.
// Android's CellConnectScreen, word for word.
import SwiftUI

/// The screen's words — pure, so the tests pin them (Android's CellConnectWords).
enum CellConnectWords {
    static let kicker = "Your cell"
    static let title = "Ask to be connected"
    static let line = "Tell the church where you live and when you're free — your pastor will connect you to a cell."
    static let area = "Where do you live?"
    static let areaHint = "Your area or estate"
    static let times = "When are you free?"
    static let timesHint = "Weekday evenings, Saturday mornings…"
    static let note = "Anything else? (optional)"
    static let ask = "Ask the church"
    static let open = "Open the conversation"
    static let sentLine = "Your pastor has your request in your conversation together."
    /// YOUR WEEK's line before asking.
    static let weekLine = "Ask to be connected — tell the church where you live."

    /// "Sent to your pastor on Mon 5 Oct — they'll connect you" (the year when
    /// it isn't this year), on the church's calendar.
    static func sent(_ requestedAt: String, now: Date = Date(), timeZone: TimeZone = GiveCalendar.nairobi) -> String {
        guard let at = ISO8601DateFormatter.nuru.date(from: requestedAt) ?? ISO8601DateFormatter().date(from: requestedAt) else {
            return "Sent to your pastor — they'll connect you"
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = cal.component(.year, from: at) == cal.component(.year, from: now) ? "EEE d MMM" : "EEE d MMM yyyy"
        return "Sent to your pastor on \(f.string(from: at)) — they'll connect you"
    }

    /// The server's bounds (2–80, 2–120, ≤300): "Ask the church" waits for them.
    static func canAsk(area: String, availability: String, note: String) -> Bool {
        let a = area.trimmingCharacters(in: .whitespacesAndNewlines).count
        let t = availability.trimmingCharacters(in: .whitespacesAndNewlines).count
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (2...80).contains(a) && (2...120).contains(t) && n <= 300
    }
}

@MainActor
final class CellConnectViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        /// The form.
        case asking
        /// Asked: when, and the conversation it went into.
        case sent(requestedAt: String, conversationId: String)
        /// Already in a cell — the cell page instead.
        case inCell
        /// The server's own words (a minor; no pastor), with Go back.
        case refused(String)
        /// The status didn't load — §4's words.
        case failed(NuruStateCopy)
    }

    @Published var phase: Phase = .loading
    @Published var sending = false
    /// Why the last send didn't land — above the button; the words stay.
    @Published var sendError: String?
    /// One per ask, kept across retries.
    private(set) var clientMutationId = UUID().uuidString

    func load() async {
        phase = .loading
        do {
            let s = try await MemberAPI.cellConnection()
            if s.inCell { phase = .inCell }
            else if let r = s.request { phase = .sent(requestedAt: r.requestedAt, conversationId: r.conversationId) }
            else { phase = .asking }
        } catch {
            phase = .failed(NuruStateCopy.failure(error))
        }
    }

    func ask(area: String, availability: String, note: String) async {
        guard !sending else { return }
        sending = true; sendError = nil
        defer { sending = false }
        do {
            let r = try await MemberAPI.askToBeConnected(area: area, availability: availability, note: note,
                                                         clientMutationId: clientMutationId)
            Haptics.success()
            phase = .sent(requestedAt: r.requestedAt, conversationId: r.conversationId)
        } catch let APIError.http(status, _, message, _) where status == 409 {
            // "You're already in a cell." — the cell page says the rest.
            _ = message
            phase = .inCell
        } catch {
            let copy = NuruStateCopy.failure(error)
            if copy.cause == .refusal {
                phase = .refused(copy.title)
            } else {
                sendError = NuruStateCopy.sendFailureLine(error, kept: "")
                    .trimmingCharacters(in: .whitespaces)
                Haptics.error()
            }
        }
    }
}

struct CellConnectView: View {
    @StateObject private var vm = CellConnectViewModel()
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    @State private var area = ""
    @State private var availability = ""
    @State private var note = ""
    @FocusState private var focused: Field?
    private enum Field { case area, times, note }

    var body: some View {
        Group {
            if vm.phase == .inCell {
                // Already in a cell: the cell page itself (its own header and back).
                CellInfoView()
            } else {
                page
            }
        }
        .task { if vm.phase == .loading { await vm.load() } }
    }

    private var page: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Nuru.S.lg) {
                    backButton
                    NuruHeaderText(kicker: CellConnectWords.kicker, title: CellConnectWords.title,
                                   line: CellConnectWords.line)
                    content
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, NuruSafeArea.top + 8)
                .padding(.bottom, Nuru.S.lg)
            }
            if case .asking = vm.phase { askBar }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .ignoresSafeArea(edges: .top)
    }

    private var backButton: some View {
        Button { Haptics.tap(); dismiss() } label: {
            Icon(.arrowLeft, size: 18, color: Nuru.navy)
                .frame(width: 40, height: 40)
                .background(Nuru.white, in: Circle())
                .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Back")
    }

    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .loading:
            NuruStateView(state: .loading)
        case .failed(let copy):
            NuruStateView(state: .failed(copy), retry: { Task { await vm.load() } }, back: { dismiss() })
        case .refused(let words):
            NuruStateView(state: .failed(NuruStateCopy(cause: .refusal, title: words, line: nil, action: .goBack)),
                          back: { dismiss() })
        case let .sent(at, conversationId):
            Card {
                VStack(alignment: .leading, spacing: Nuru.S.md) {
                    HStack(alignment: .top, spacing: Nuru.S.md) {
                        Icon(.send, size: 18, color: Nuru.navy)
                            .frame(width: 36, height: 36)
                            .background(Color(hex: Nuru.tileTint), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(CellConnectWords.sent(at))
                                .font(.nRowTitle).foregroundStyle(Nuru.navy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(CellConnectWords.sentLine)
                                .font(.nBody).foregroundStyle(Nuru.ink600)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    PButton(title: CellConnectWords.open, variant: .secondary) {
                        Haptics.tap()
                        tabs.openConversation(conversationId)
                    }
                }
            }
        case .asking:
            Card {
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    field(CellConnectWords.area, hint: CellConnectWords.areaHint, text: $area, focus: .area)
                    field(CellConnectWords.times, hint: CellConnectWords.timesHint, text: $availability, focus: .times)
                    field(CellConnectWords.note, hint: "", text: $note, focus: .note, lines: 3)
                }
            }
        case .inCell:
            EmptyView()
        }
    }

    private func field(_ label: String, hint: String, text: Binding<String>, focus: Field, lines: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.inter(14, .medium)).foregroundStyle(Nuru.navy)
            TextField(hint, text: text, axis: .vertical)
                .lineLimit(lines...max(lines, 5))
                .font(.nBody).foregroundStyle(Nuru.ink)
                .focused($focused, equals: focus)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Nuru.inputBg, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                .submitLabel(focus == .note ? .done : .next)
        }
    }

    /// The one primary, above the tab bar; why a send failed sits above it.
    private var askBar: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            if let e = vm.sendError {
                Text(e).font(.nCardBody).foregroundStyle(Nuru.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PButton(title: CellConnectWords.ask, busy: vm.sending,
                    disabled: !CellConnectWords.canAsk(area: area, availability: availability, note: note)) {
                focused = nil
                Task { await vm.ask(area: area, availability: availability, note: note) }
            }
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.md)
        .padding(.bottom, Nuru.tabBarSpace - 30)
        .background(Nuru.paper.ignoresSafeArea(edges: .bottom))
    }
}
