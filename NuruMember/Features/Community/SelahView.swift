// Selah — My Thoughts (Prayer Room tab 3, docs: prayer-room-arc). Owner spec
// 2026-07-18: "Selah — a word from the Psalms meaning pause and reflect. This
// is your quiet page: write what's on your heart. Only you can see it." A
// private, rich-text + pen journal — no leader/admin read path exists for this
// domain, by design (§5.4).
import SwiftUI

@MainActor
final class ThoughtsViewModel: ObservableObject {
    @Published var thoughts: [Thought] = []
    @Published var loading = true
    @Published var error: String?

    // Offline-first (§1.7), exactly like PrayerJournalViewModel: instant read
    // from the encrypted cache, refresh from the network, writes go through the
    // durable mutation queue (member_thoughts:upsert / :delete, wired server-
    // side in the sync module).
    private let sync = SyncCoordinator.shared
    private let domain = "member_thoughts"

    func load() async {
        error = nil
        let cachedList = await cached()
        if !cachedList.isEmpty { thoughts = cachedList; loading = false }
        if let fresh = try? await MemberAPI.thoughts() {
            thoughts = fresh.sorted { $0.createdAt > $1.createdAt }
            await cacheAll(thoughts)
        } else if cachedList.isEmpty {
            error = "You're offline — Selah will load when you reconnect."
        }
        loading = false
    }

    func upsert(_ draft: SelahDraft) async {
        let now = ISO8601DateFormatter().string(from: Date())
        let existing = thoughts.first { $0.thoughtId == draft.thoughtId }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = Thought(thoughtId: draft.thoughtId, title: title.isEmpty ? nil : title, body: draft.body,
                         bodySpans: draft.spans.isEmpty ? nil : draft.spans, drawingUrls: draft.drawingUrls,
                         createdAt: existing?.createdAt ?? now, updatedAt: now)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let i = thoughts.firstIndex(where: { $0.thoughtId == draft.thoughtId }) { thoughts[i] = t }
            else { thoughts.insert(t, at: 0) }
        }
        await cacheAll(thoughts)
        await sync.enqueue(domain: domain, op: "upsert", payload: [
            "thought_id": AnyCodable(draft.thoughtId),
            "title": AnyCodable(t.title),
            "body": AnyCodable(t.body),
            "body_spans": AnyCodable(draft.spans.map(Self.spanDict)),
            "drawing_urls": AnyCodable(draft.drawingUrls.map { AnyCodable($0) }),
            "updated_at": AnyCodable(now),
        ])
    }

    func delete(_ t: Thought) async {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            thoughts.removeAll { $0.thoughtId == t.thoughtId }
        }
        await cacheAll(thoughts)
        await sync.enqueue(domain: domain, op: "delete", payload: ["thought_id": AnyCodable(t.thoughtId)])
    }

    private static func spanDict(_ s: ThoughtSpan) -> AnyCodable {
        var d: [String: AnyCodable] = ["start": AnyCodable(s.start), "end": AnyCodable(s.end)]
        if let b = s.bold { d["bold"] = AnyCodable(b) }
        if let i = s.italic { d["italic"] = AnyCodable(i) }
        if let c = s.color { d["color"] = AnyCodable(c) }
        if let f = s.font { d["font"] = AnyCodable(f) }
        return AnyCodable(d)
    }

    private func cacheAll(_ list: [Thought]) async {
        let rows = list.compactMap { t -> (id: String, body: Data)? in
            (try? JSONEncoder.nuruSnake.encode(t)).map { (t.thoughtId, $0) }
        }
        await sync.store.cacheReplace(domain: domain, rows: rows)
    }

    private func cached() async -> [Thought] {
        await sync.store.cachedRows(domain: domain)
            .compactMap { try? JSONDecoder.nuruSnake.decode(Thought.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

struct SelahView: View {
    @StateObject private var vm = ThoughtsViewModel()
    @State private var editing: SelahDraft?
    @AppStorage("nuru.selah.explainerDismissed") private var explainerDismissed = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Nuru.paper.ignoresSafeArea()
            LoadStateView(loading: vm.loading && vm.thoughts.isEmpty,
                          isEmpty: vm.error != nil && vm.thoughts.isEmpty,
                          error: vm.error, emptyText: "",
                          retry: { Task { await vm.load() } }) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Nuru.S.base) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pause. Reflect. Write.")
                                .font(.fraunces(21, .medium)).foregroundStyle(Nuru.navy)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gentleEntrance()

                        if !explainerDismissed {
                            ExplainerCard { withAnimation { explainerDismissed = true } }
                                .gentleEntrance(delay: 0.05)
                        }

                        HStack {
                            Spacer(minLength: 0)
                            Button { Haptics.tap(); editing = SelahDraft() } label: {
                                HStack(spacing: 5) {
                                    Icon(.plus, size: 13, color: .white)
                                    Text("New Thought").font(.nActionLabel).foregroundStyle(.white)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(
                                    LinearGradient(colors: [Color(hex: 0xE0B85E), Color(hex: 0xC9A227)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: Capsule())
                                .shadow(color: Color(hex: 0xC9A227).opacity(0.35), radius: 6, y: 3)
                            }
                            .buttonStyle(.pressable)
                        }
                        .gentleEntrance(delay: 0.08)

                        if vm.thoughts.isEmpty {
                            EmptyThoughts { editing = SelahDraft() }
                        } else {
                            ForEach(Array(vm.thoughts.enumerated()), id: \.element.id) { idx, t in
                                ThoughtRowCard(thought: t) { editing = SelahDraft(t) }
                                    .gentleEntrance(delay: 0.1 + min(Double(idx), 3) * 0.05)
                            }
                        }
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.lg)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
                .refreshable { await vm.load() }
            }
        }
        .task { if vm.thoughts.isEmpty { await vm.load() } }
        .fullScreenCover(item: $editing) { draft in
            SelahEditorView(
                draft: draft,
                onSave: { d in Task { await vm.upsert(d) } },
                onDelete: draft.isNew ? nil : {
                    if let t = vm.thoughts.first(where: { $0.thoughtId == draft.thoughtId }) {
                        Task { await vm.delete(t) }
                    }
                })
        }
    }
}

// MARK: - One-time explainer (dismissible, persisted — @AppStorage, readerNight idiom)

private struct ExplainerCard: View {
    let dismiss: () -> Void
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Nuru.S.sm) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Nuru.surface)
                    .frame(width: 40, height: 40)
                    .overlay(Icon(.bookOpen, size: 18, color: Nuru.gold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selah — a word from the Psalms meaning pause and reflect. This is your quiet page: write what's on your heart. Only you can see it.")
                        .font(.nCardBody).foregroundStyle(Color(hex: 0x3A4A5F)).lineSpacing(3)
                }
                Spacer(minLength: 0)
                Button { Haptics.tap(); dismiss() } label: {
                    Icon(.x, size: 13, color: Color(hex: 0x74808F))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyThoughts: View {
    let compose: () -> Void
    var body: some View {
        Card {
            VStack(spacing: Nuru.S.sm) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Nuru.surface)
                    .frame(width: 48, height: 48)
                    .overlay(Icon(.bookOpen, size: 20, color: Nuru.gold))
                Text("Selah. Pause here — write your first thought.")
                    .font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Nuru.S.lg)
            .contentShape(Rectangle())
            .onTapGesture { compose() }
        }
    }
}

// MARK: - Thought row

private struct ThoughtRowCard: View {
    let thought: Thought
    let open: () -> Void

    private var preview: String {
        let flat = thought.body.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > 140 ? String(flat.prefix(140)) + "…" : flat
    }

    var body: some View {
        Button { Haptics.tap(); open() } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(thought.title?.isEmpty == false ? thought.title! : "Untitled")
                        .font(.nRowTitle).foregroundStyle(Nuru.navy)
                        .lineLimit(1)
                    Spacer(minLength: Nuru.S.sm)
                    if !thought.drawingUrls.isEmpty {
                        Icon(.pencil, size: 12, color: Color(hex: 0x9A7A2A))
                    }
                    Text(relativeThoughtLabel(thought.updatedAt))
                        .font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F))
                }
                if !preview.isEmpty {
                    Text(preview)
                        .font(.nCardBody).foregroundStyle(Color(hex: 0x3A4A5F))
                        .lineLimit(2)
                }
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow(0.6)
        }
        .buttonStyle(.plain)
    }
}

private func relativeThoughtLabel(_ iso: String) -> String {
    guard let d = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
    switch days {
    case ..<1: return "today"
    case 1: return "1 day ago"
    case ..<7: return "\(days) days ago"
    default:
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}
