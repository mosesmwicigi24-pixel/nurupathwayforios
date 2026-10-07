// The member's own archive of past Sunday Letters — GET /me/letters (already
// shipped for Phase 1's "latest" card; this is the first UI to browse the
// full history). Reached from inside LetterView ("Past letters"), so it's one
// tap deep from wherever a member is already reading a letter — the natural
// place for "read another one" to live, and it means opening an archived
// letter reuses LetterView's rendering (hero, moments, everything) for free.
import SwiftUI

struct LetterArchiveView: View {
    @State private var letters: [PastoralLetter]
    @State private var loading: Bool
    /// Why the letters didn't come, said in §4's words (it read "Check
    /// your connection" whatever the cause).
    @State private var loadFailure: Error?
    /// The letters open over the list, oldest last: each letter's "Last
    /// week" turns to the one before it in place, and back returns, letter
    /// by letter, to the list (owner, 2026-10-07; Android's archive).
    @State private var path: [LetterRoute]
    /// A letter the archive opened on, until the list has it.
    private let opening: PastoralLetter?
    @Environment(\.dismiss) private var dismiss

    /// The archive, or — `opening` a letter, from the editorial letter's
    /// "Last week" — that letter, with the list behind it. `known`: the
    /// letters the caller already has, so the list shows at once.
    init(opening: PastoralLetter? = nil, known: [PastoralLetter] = []) {
        self.opening = opening
        _letters = State(initialValue: known)
        _loading = State(initialValue: known.isEmpty)
        _path = State(initialValue: opening.map { [LetterRoute(id: $0.letterId)] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x081020)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if loading {
                    ProgressView().tint(Nuru.gold)
                } else if letters.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(letters) { lt in
                                Button {
                                    Haptics.tap()
                                    path.append(LetterRoute(id: lt.letterId))
                                } label: {
                                    row(lt)
                                }
                                .buttonStyle(.pressableSubtle)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Your Letters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .tint(.white)
                }
            }
            .navigationDestination(for: LetterRoute.self) { route in letterPage(route.id) }
        }
        .task { await load() }
    }

    /// One letter, full page, over the list: its close and the edge swipe go
    /// back; its "Last week" opens the letter before it here.
    @ViewBuilder private func letterPage(_ id: String) -> some View {
        if let lt = letters.first(where: { $0.letterId == id }) ?? opening.flatMap({ $0.letterId == id ? $0 : nil }) {
            LetterView(letter: lt, archive: letters, openEarlier: { path.append(LetterRoute(id: $0.letterId)) })
                .toolbar(.hidden, for: .navigationBar)
                .nuruEdgeSwipeBack()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Icon(.mail, size: 30, color: Color(hex: 0x6B7A8F))
            Text(loadFailure.map { NuruStateCopy.failure($0).title } ?? "No letters yet")
                .font(.fraunces(18, .semibold)).foregroundStyle(.white)
            Text(loadFailure.map { NuruStateCopy.failure($0).line ?? "" }
                 ?? "One arrives every Sunday evening, written from your own week.")
                .font(.inter(13)).foregroundStyle(Color(hex: 0x9AA8BC))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func row(_ lt: PastoralLetter) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LetterTheme.resolve(lt.imageKey).accentColor.opacity(0.9))
                    .frame(width: 40, height: 40)
                Icon(.mail, size: 18, color: Color(hex: 0x1E2A1F))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(lt.title).font(.fraunces(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(weekLabel(lt.weekOf)).font(.inter(11)).foregroundStyle(Color(hex: 0x8A97AA))
            }
            Spacer(minLength: 0)
            if lt.isUnread {
                Circle().fill(Nuru.gold).frame(width: 7, height: 7)
            }
            Icon(.chevronRight, size: 14, color: Color(hex: 0x5C6B80))
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func weekLabel(_ raw: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: raw) else { return raw }
        return "Week of \(NuruDates.day(d))"   // the one date shape (§8.1 rule 8)
    }

    private func load() async {
        do {
            letters = try await MemberAPI.letters()
        } catch {
            // The letters the caller handed over still stand.
            if letters.isEmpty { loadFailure = error }
        }
        loading = false
    }
}

/// A letter on the archive's stack, by id.
struct LetterRoute: Hashable {
    let id: String
}
