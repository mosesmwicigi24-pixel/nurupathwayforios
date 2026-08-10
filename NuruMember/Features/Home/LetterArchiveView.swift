// The member's own archive of past Sunday Letters — GET /me/letters (already
// shipped for Phase 1's "latest" card; this is the first UI to browse the
// full history). Reached from inside LetterView ("Past letters"), so it's one
// tap deep from wherever a member is already reading a letter — the natural
// place for "read another one" to live, and it means opening an archived
// letter reuses LetterView's rendering (hero, moments, everything) for free.
import SwiftUI

struct LetterArchiveView: View {
    @State private var letters: [PastoralLetter] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var selected: PastoralLetter?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
                                    selected = lt
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
        }
        .task { await load() }
        .sheet(item: $selected) { lt in LetterView(letter: lt) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Icon(.mail, size: 30, color: Color(hex: 0x6B7A8F))
            Text(loadFailed ? "Couldn't load your letters" : "No letters yet")
                .font(.fraunces(17, .semibold)).foregroundStyle(.white)
            Text(loadFailed
                 ? "Check your connection and try again."
                 : "One arrives every Sunday evening, written from your own week.")
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
                Icon(.mail, size: 16, color: Color(hex: 0x1E2A1F))
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
        let out = DateFormatter(); out.dateFormat = "d MMMM yyyy"
        return "Week of \(out.string(from: d))"
    }

    private func load() async {
        do {
            letters = try await MemberAPI.letters()
        } catch {
            loadFailed = true
        }
        loading = false
    }
}
