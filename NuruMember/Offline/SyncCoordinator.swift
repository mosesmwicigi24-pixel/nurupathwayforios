// Live wiring for the offline-first engine (§1.7): connectivity monitoring +
// automatic flush. The app holds one shared coordinator; feature screens enqueue
// offline-capable writes through it and read cached data when the network is down.
//
// Flush triggers: app launch, network reconnect, return to foreground, and right
// after an enqueue while online. The mutation queue (encrypted, durable) is the
// system of record — a write "succeeds" the moment it is queued; the server catch-up
// is idempotent, so replays are no-ops. Money is refused at the queue (§5.6).
import Foundation
import Network
import Combine

@MainActor
final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    @Published private(set) var isOnline = true
    @Published private(set) var pendingCount = 0
    @Published private(set) var isSyncing = false

    /// The encrypted store, exposed so feature view-models can read/write the cache.
    let store: EncryptedSQLiteStore
    private let engine: SyncEngine
    private let monitor = NWPathMonitor()
    private var started = false

    /// Read domains kept warm in the encrypted cache via background delta pulls, so
    /// their screens open instantly and work offline with last-known server data.
    private let pullDomains = [
        "prayer_entries", "saved_verses", "event_rsvps", "module_progress",
        "module_reflections", "gift_assessments", "enrollments",
        "discussion_threads", "discussion_comments", "member_thoughts",
    ]

    init(store: EncryptedSQLiteStore = EncryptedSQLiteStore()) {
        self.store = store
        self.engine = SyncEngine(store: store)
    }

    /// Begin connectivity monitoring and drain anything already queued. Idempotent.
    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let reconnected = online && !self.isOnline
                self.isOnline = online
                if reconnected { await self.flush(); await self.pull(domains: self.pullDomains) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "org.nuruplace.member.connectivity"))
        Task { await self.refreshPending(); await self.flush(); await self.pull(domains: self.pullDomains) }
    }

    /// Enqueue an offline-capable write (durably), then flush immediately if online.
    /// Returns false only if the domain is refused (e.g. money, §5.6).
    @discardableResult
    func enqueue(domain: String, op: String, payload: [String: AnyCodable]) async -> Bool {
        do { _ = try await engine.enqueue(domain: domain, op: op, payload: payload) }
        catch { return false }
        await refreshPending()
        if isOnline { await flush() }
        return true
    }

    /// Replay the queue against the server (no-op when offline / already syncing).
    func flush() async {
        guard isOnline, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        _ = try? await engine.push()
        await refreshPending()
    }

    /// Pull server deltas for the given domains (advances cursors).
    func pull(domains: [String]) async {
        guard isOnline else { return }
        _ = try? await engine.pull(domains: domains)
    }

    private func refreshPending() async {
        pendingCount = await store.pendingMutations().count
    }
}
