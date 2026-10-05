// One state language (pathway docs/EXPERIENCE.md §4) — what a screen shows
// instead of its content: loading, empty, or why it failed, in ONE look and
// in words that say what really happened. Raw server or exception text never
// reaches a member: a dead session says so, a 5xx says it was us, and only a
// phone with no network is told it is offline — a call that got no answer
// while the phone HAS a network was failed by our side, never by its
// connection. Only our own API's member-facing refusals (a 4xx that carries
// our error envelope) keep their words, as the server wrote them.
import SwiftUI

/// What a failure means to the member, in §4's words. Pure — the mapper is
/// the contract, and the tests pin it.
struct NuruStateCopy: Equatable {
    enum Cause: Equatable { case offline, sessionEnded, serverSide, notFound, refusal }
    enum Action: Equatable { case retry, signIn, goBack }

    let cause: Cause
    let title: String
    let line: String?
    /// Nil for a refusal — the screen offers what it needs (a load: Try again).
    let action: Action?

    /// The one-line form, for a note under a button, a sheet's error line or
    /// an alert's message: "Title. Line" — or the title alone (a refusal is
    /// a whole sentence of the server's). Android's StateMessage.sentence.
    var sentence: String { line.map { "\(title). \($0)" } ?? title }

    /// The server's generic body-parse refusal (400 VALIDATION_FAILED, Zod):
    /// the app sent a request the server couldn't read — our side's fault,
    /// not words written for a member (EXPERIENCE.md §7.3). Other
    /// VALIDATION_FAILED answers carry real words ("That code is not valid")
    /// and keep them.
    static let bodyParseRefusal = "Request body failed validation"

    /// The phone has no network. `showingSaved` when the screen still shows
    /// what it last loaded; otherwise there is nothing to fall back on.
    static func offline(showingSaved: Bool) -> NuruStateCopy {
        NuruStateCopy(cause: .offline, title: "You're offline",
                      line: showingSaved ? "Showing what you last saw — we'll refresh when you're back."
                                         : "Connect to the internet, then try again.",
                      action: .retry)
    }
    /// A 401 the refresh token could not answer.
    static let sessionEnded = NuruStateCopy(
        cause: .sessionEnded, title: "Your session has ended",
        line: "Sign in again to pick up where you left off.", action: .signIn)
    /// A 5xx, or an answer this build could not read.
    static let serverSide = NuruStateCopy(
        cause: .serverSide, title: "Something went wrong on our side",
        line: "It isn't you — please try again in a moment.", action: .retry)
    static let notFound = NuruStateCopy(
        cause: .notFound, title: "This isn't here any more",
        line: "It may have been moved or removed.", action: .goBack)

    /// `deviceOnline` is the phone's own network path (SyncCoordinator's
    /// monitor) — injected, so the tests pin both branches.
    static func failure(_ error: Error, showingSaved: Bool = false,
                        deviceOnline: Bool? = SyncCoordinator.devicePathOnline) -> NuruStateCopy {
        guard let api = error as? APIError else {
            return error is URLError ? noAnswer(deviceOnline: deviceOnline, showingSaved: showingSaved) : serverSide
        }
        switch api {
        case .offline, .transport:
            return noAnswer(deviceOnline: deviceOnline, showingSaved: showingSaved)
        case .unauthorized:
            return sessionEnded
        case .decoding:
            return serverSide
        case let .http(status, code, message, _):
            if status == 401 { return sessionEnded }
            if status == 404 { return notFound }
            // Our own words only: a 4xx without our envelope (a proxy's page,
            // a bare status) is not something we said to the member — nor is
            // the generic body-parse refusal (§7.3): that one is ours.
            let words = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if code == "VALIDATION_FAILED", words == bodyParseRefusal { return serverSide }
            if (400..<500).contains(status), code != nil, !words.isEmpty {
                return NuruStateCopy(cause: .refusal, title: words, line: nil, action: nil)
            }
            return serverSide
        }
    }

    /// A call that got no answer (no network, a timeout, a host that didn't
    /// pick up): offline only when the DEVICE has no network path. A phone
    /// that has one and still got no answer was failed by our side. Unknown
    /// (the monitor hasn't reported yet): offline — this build can't tell a
    /// timeout from a dropped network once the request has failed.
    static func noAnswer(deviceOnline: Bool?, showingSaved: Bool) -> NuruStateCopy {
        deviceOnline == true ? serverSide : offline(showingSaved: showingSaved)
    }
}

extension NuruStateCopy {
    /// A write the server did not record (EXPERIENCE.md §7.4 #2): the member
    /// stays where they are, and the line above the button that tried says
    /// so in §4's words — "Couldn't save that." and why. Never a success the
    /// server didn't give. Android's words and place.
    static func saveFailureLine(_ error: Error, deviceOnline: Bool? = SyncCoordinator.devicePathOnline) -> String {
        "Couldn't save that. " + failure(error, deviceOnline: deviceOnline).sentence
    }

    /// A message, comment or recording the server did not take (Cycle 4, the
    /// lost-input class): it stays where the member left it, and this line
    /// says so — "Couldn't send that.", why, and what is kept for a retry.
    /// A delete the server did not do: the thing is still there, and says so.
    static func deleteFailureLine(_ error: Error, deviceOnline: Bool? = SyncCoordinator.devicePathOnline) -> String {
        "Couldn't delete that. " + failure(error, deviceOnline: deviceOnline).sentence + " It's still here."
    }

    static func sendFailureLine(_ error: Error, kept: String = "Your words are kept — send again when you're ready.",
                                deviceOnline: Bool? = SyncCoordinator.devicePathOnline) -> String {
        "Couldn't send that. " + failure(error, deviceOnline: deviceOnline).sentence + " " + kept
    }
}

/// What a screen shows in place of its content.
enum NuruState: Equatable {
    case loading
    case empty(title: String, line: String? = nil)
    case failed(NuruStateCopy)

    /// The one rule every list screen follows: content wins whenever there is
    /// any; otherwise loading, then the failure, then the screen's empty words.
    /// Nil means "show the content".
    static func resolve(loading: Bool, isEmpty: Bool, failure: Error?, empty: NuruState,
                        deviceOnline: Bool? = SyncCoordinator.devicePathOnline) -> NuruState? {
        guard isEmpty else { return nil }
        if loading { return .loading }
        if let failure { return .failed(.failure(failure, deviceOnline: deviceOnline)) }
        return empty
    }
}

/// The ONE view for loading / empty / failed — full width, in the app's card
/// style (white, hairline, one soft shadow). `compact` is the slim row for a
/// screen whose other sections still stand (Home's dashboard strip).
struct NuruStateView: View {
    let state: NuruState
    /// The screen's reload — "Try again", and the answer to a refusal.
    var retry: (() -> Void)? = nil
    /// The screen's way back, for "This isn't here any more".
    var back: (() -> Void)? = nil
    var compact = false
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        if compact { strip } else { card }
    }

    // MARK: Layouts

    private var card: some View {
        VStack(spacing: 0) {
            if state == .loading {
                ProgressView().tint(Nuru.gold).frame(height: 44)
                    .accessibilityLabel("Loading")
            } else {
                glyph(tile: 48, size: 22)
                Text(title)
                    .font(.nCardTitle).foregroundStyle(Nuru.navy)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                if let line {
                    Text(line)
                        .font(.nCardBody).foregroundStyle(Nuru.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                if let action {
                    Button { Haptics.tap(); action.run() } label: {
                        Text(action.label).font(.nCardCTA).foregroundStyle(Nuru.gold)
                            .padding(.horizontal, 22).padding(.vertical, 11)
                            .background(Nuru.navy, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 18)
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.vertical, 28)
        // A card's look (§8.1 rule 5): white, radius 24, hairline, one shadow.
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private var strip: some View {
        HStack(spacing: 12) {
            glyph(tile: 36, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    .fixedSize(horizontal: false, vertical: true)
                if let line {
                    Text(line).font(.nCardMeta).foregroundStyle(Nuru.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let action {
                Button { Haptics.tap(); action.run() } label: {
                    Text(action.label)
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.gold)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Nuru.navy, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    @ViewBuilder private func glyph(tile: CGFloat, size: CGFloat) -> some View {
        Group {
            switch cause {
            case .offline?: Icon(.wifiOff, size: size, color: Nuru.ink600)   // Lucide, not an SF Symbol (rule 7)
            case .sessionEnded?: Icon(.lockKeyhole, size: size, color: Nuru.goldLo)
            case .notFound?: Icon(.search, size: size, color: Nuru.ink600)
            case .serverSide?, .refusal?: Icon(.circleHelp, size: size, color: Nuru.ink600)
            case nil: Icon(.sparkles, size: size, color: Nuru.gold)   // empty
            }
        }
        .frame(width: tile, height: tile)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: tile / 3, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: Words + action

    private var cause: NuruStateCopy.Cause? {
        if case .failed(let c) = state { return c.cause }
        return nil
    }
    private var title: String {
        switch state {
        case .loading: return ""
        case .empty(let t, _): return t
        case .failed(let c): return c.title
        }
    }
    private var line: String? {
        switch state {
        case .loading: return nil
        case .empty(_, let l): return l
        case .failed(let c): return c.line
        }
    }

    /// The button the state earns: Sign in for an ended session (the app's
    /// own sign-out-to-login path), Go back where the screen has a way back,
    /// otherwise the screen's Try again.
    private var action: (label: String, run: () -> Void)? {
        guard case .failed(let c) = state else { return nil }
        switch c.action {
        case .signIn?:
            return ("Sign in", { auth.signOut() })
        case .goBack?:
            if let back { return ("Go back", back) }
            return retry.map { ("Try again", $0) }
        case .retry?, nil:
            return retry.map { ("Try again", $0) }
        }
    }
}
