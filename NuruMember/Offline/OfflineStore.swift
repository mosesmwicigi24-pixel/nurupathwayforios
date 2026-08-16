// Offline-first foundation (§1.7, §3.6) — the native port of
// packages/mobile/src/sync/* and src/db/*. The pending-mutations queue is the
// system of record for in-flight writes; the UI reads the local cache, so the
// member never waits on the network.
//
// This file establishes the durable contract. The per-domain pull/cache mapping
// (the long tail of ID_FIELD in syncEngine.ts) is ported domain-by-domain as the
// feature screens land — see PORT_STATUS.md. Money is never queued (§5.6).
import Foundation

// Shared coders so the on-device cache uses the SAME snake_case row shape the
// server's /sync/pull returns — a screen can read a row whether it was written by
// its own fetch or by a background delta pull.
extension JSONEncoder {
    static let nuruSnake: JSONEncoder = {
        let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; return e
    }()
}
extension JSONDecoder {
    static let nuruSnake: JSONDecoder = {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }()
}

// MARK: - Pending mutation (the durable queue entry)

struct PendingMutation: Codable, Sendable, Identifiable {
    let mutationId: String
    let seq: Int
    let domain: String
    let op: String
    let payload: [String: AnyCodable]
    var status: String   // pending | applied | duplicate | rejected

    var id: String { mutationId }
}

/// Domains whose writes must NEVER be queued offline (§5.6 — the giving flow
/// requires connectivity; cards never touch our server). Mirrors MONEY_DOMAINS.
enum MoneyDomains {
    static let all: Set<String> = ["giving", "giving_schedules", "payments"]
}

// MARK: - Local store contract

/// The durable on-device store: the mutation queue + per-domain pull cursors +
/// a cached-rows key/value space. The native equivalent of LocalStore in
/// src/db/localStore.ts. Backed on disk so it survives relaunch (§1.7).
protocol LocalStore: Sendable {
    func pendingMutations() async -> [PendingMutation]
    func enqueueMutation(_ m: PendingMutation) async
    func removeMutations(ids: [String]) async
    func cursors() async -> [String: Int]
    func setCursor(domain: String, value: Int) async

    // Per-domain read cache so screens open instantly (and work offline) with
    // last-known data. Bodies are opaque encoded blobs owned by each feature.
    func cacheUpsert(domain: String, rows: [(id: String, body: Data)]) async
    func cacheReplace(domain: String, rows: [(id: String, body: Data)]) async
    func cacheDelete(domain: String, ids: [String]) async
    func cachedRows(domain: String) async -> [Data]
}

// Default no-op cache so the lightweight `FileLocalStore` keeps conforming; the
// encrypted SQLite store provides the real implementations.
extension LocalStore {
    func cacheUpsert(domain: String, rows: [(id: String, body: Data)]) async {}
    func cacheReplace(domain: String, rows: [(id: String, body: Data)]) async {}
    func cacheDelete(domain: String, ids: [String]) async {}
    func cachedRows(domain: String) async -> [Data] { [] }
}

// MARK: - File-backed local store

/// A JSON-file-backed LocalStore in Application Support. Adequate for the queue +
/// cursors; the cached-content tables move to an SQLCipher store (op-sqlite parity)
/// in a later phase, behind this same protocol.
actor FileLocalStore: LocalStore {
    private struct Snapshot: Codable {
        var mutations: [PendingMutation] = []
        var cursors: [String: Int] = [:]
    }

    private let url: URL
    private var snapshot: Snapshot

    init(filename: String = "nuru-offline.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: url),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = snap
        } else {
            snapshot = Snapshot()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }

    func pendingMutations() -> [PendingMutation] { snapshot.mutations }

    func enqueueMutation(_ m: PendingMutation) {
        snapshot.mutations.append(m)
        persist()
    }

    func removeMutations(ids: [String]) {
        let set = Set(ids)
        snapshot.mutations.removeAll { set.contains($0.mutationId) }
        persist()
    }

    func cursors() -> [String: Int] { snapshot.cursors }

    func setCursor(domain: String, value: Int) {
        snapshot.cursors[domain] = value
        persist()
    }
}

// MARK: - Sync engine

/// Wraps the two server flows around the local store (§1.7, §3.6):
///   • enqueue — append an intent to the durable pending-mutations queue
///   • push    — replay the queue in seq order; drop applied/duplicate/rejected
///   • pull     — cursor-driven delta (skeleton; per-domain cache lands later)
actor SyncEngine {
    private let store: LocalStore
    private let deviceId: String?

    init(store: LocalStore, deviceId: String? = nil) {
        self.store = store
        self.deviceId = deviceId
    }

    /// Append an offline mutation with the next monotonic per-device seq.
    /// Refuses money at the source (§5.6).
    @discardableResult
    func enqueue(domain: String, op: String, payload: [String: AnyCodable]) async throws -> PendingMutation {
        guard !MoneyDomains.all.contains(domain) else {
            throw APIError.transport("Money is never queued offline (§5.6); the giving flow requires connectivity.")
        }
        let pending = await store.pendingMutations()
        let seq = (pending.map(\.seq).max() ?? 0) + 1
        let mutation = PendingMutation(
            mutationId: UUID().uuidString,
            seq: seq,
            domain: domain,
            op: op,
            payload: payload,
            status: "pending"
        )
        await store.enqueueMutation(mutation)
        return mutation
    }

    /// Replay the queue. Returns the server result, or nil if nothing was queued.
    @discardableResult
    func push() async throws -> SyncPushResponse? {
        let mutations = await store.pendingMutations()
        guard !mutations.isEmpty else { return nil }
        struct Body: Encodable { let deviceId: String?; let mutations: [PendingMutation] }
        let res = try await APIClient.shared.post(
            "sync/push", body: Body(deviceId: deviceId, mutations: mutations), as: SyncPushResponse.self)
        // applied + duplicate + rejected all leave the queue (§3.6).
        let settled = res.results.filter { ["applied", "duplicate", "rejected"].contains($0.status) }
        await store.removeMutations(ids: settled.map(\.mutationId))
        return res
    }

    /// Server pull-domain → its primary-key field in the returned rows (snake_case).
    /// Mirrors PULL_DOMAINS `idCol` in the backend sync service.
    static let pullIdField: [String: String] = [
        "modules": "module_id", "module_progress": "progress_id", "quiz_attempts": "attempt_id",
        "level_exam_attempts": "exam_attempt_id", "enrollments": "enrollment_id",
        "video_progress": "media_asset_id", "event_rsvps": "rsvp_id",
        "module_reflections": "reflection_id", "achievements": "user_badge_id",
        "prayer_entries": "entry_id", "saved_verses": "saved_verse_id",
        "gift_assessments": "assessment_id", "discussion_threads": "thread_id",
        "discussion_comments": "comment_id", "member_thoughts": "thought_id",
    ]

    /// Cursor-driven delta pull: applies changed rows (upserts) and tombstones
    /// (deletes) into the encrypted cache, then advances the per-domain cursors —
    /// so cached screens stay fresh and readable offline. Rows are stored verbatim
    /// (snake_case) as the server sent them; readers decode with convertFromSnakeCase.
    @discardableResult
    func pull(domains: [String]) async throws -> SyncPullResponse {
        let cursors = await store.cursors()
        struct Body: Encodable { let deviceId: String?; let cursors: [String: Int] }
        let raw = try await APIClient.shared.postRaw("sync/pull", body: Body(deviceId: deviceId, cursors: cursors))
        guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            return SyncPullResponse(cursors: [:])
        }

        if let changes = obj["changes"] as? [String: [[String: Any]]] {
            for (domain, entries) in changes {
                guard let idField = Self.pullIdField[domain] else { continue }
                let rows: [(id: String, body: Data)] = entries.compactMap { entry in
                    guard let row = entry["row"] as? [String: Any],
                          let idVal = row[idField], !(idVal is NSNull),
                          let body = try? JSONSerialization.data(withJSONObject: row) else { return nil }
                    return (id: "\(idVal)", body: body)
                }
                await store.cacheUpsert(domain: domain, rows: rows)
            }
        }
        if let tombstones = obj["tombstones"] as? [String: [String]] {
            for (domain, ids) in tombstones { await store.cacheDelete(domain: domain, ids: ids) }
        }

        var newCursors: [String: Int] = [:]
        if let cs = obj["cursors"] as? [String: Any] {
            for (domain, value) in cs {
                let n = (value as? Int) ?? Int("\(value)") ?? 0
                await store.setCursor(domain: domain, value: n)
                newCursors[domain] = n
            }
        }
        return SyncPullResponse(cursors: newCursors)
    }
}

// MARK: - Sync wire shapes (subset)

struct SyncPushResponse: Decodable, Sendable {
    struct Result: Decodable, Sendable { let mutationId: String; let status: String }
    let results: [Result]
}

struct SyncPullResponse: Decodable, Sendable {
    let cursors: [String: Int]
    // Per-domain change sets are decoded by each domain's cache adapter (later phase).
}

// MARK: - AnyCodable (JSON payloads of arbitrary shape, for the queue)

/// A minimal type-erased Codable for mutation payloads — the queue stores the
/// exact JSON the server expects without a concrete type per domain.
struct AnyCodable: Codable, Sendable {
    let value: (any Sendable)?

    init(_ value: (any Sendable)?) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([AnyCodable].self) { value = a }
        else if let o = try? c.decode([String: AnyCodable].self) { value = o }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        guard let value else { try c.encodeNil(); return }
        switch value {
        case let b as Bool: try c.encode(b)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let a as [AnyCodable]: try c.encode(a)
        case let o as [String: AnyCodable]: try c.encode(o)
        default: try c.encodeNil()
        }
    }
}
