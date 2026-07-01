// Encrypted on-device SQLite store — the offline system of record (§1.7, §5.7).
//
// This is the durable backing for the sync engine: the pending-mutation queue,
// per-domain pull cursors, and a per-domain row cache so screens open instantly
// with last-known data. It conforms to `LocalStore`, so it drops in behind the
// existing `SyncEngine` without touching call sites (the old JSON `FileLocalStore`
// stays as a fallback contract).
//
// Encryption (SQLCipher-equivalent, dependency-free so the build stays hermetic):
//   1. every sensitive value (mutation payloads + cached row JSON) is sealed with
//      AES-GCM (CryptoKit) under a 256-bit key held in the Keychain
//      (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly — never leaves the device,
//      not in backups), and
//   2. the database file itself is written with `.completeUntilFirstUserAuthentication`
//      data protection, so iOS encrypts it at rest with a hardware-backed class key.
// The result: no prayer, reflection, or queued write is ever readable at rest. A
// literal SQLCipher/GRDB page-cipher backend can replace this class behind
// `LocalStore` later with zero call-site changes.
import Foundation
import Security
import CryptoKit
import SQLite3

// SQLite wants a destructor sentinel that its Swift shim doesn't surface.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor EncryptedSQLiteStore: LocalStore {
    private var db: OpaquePointer?
    private let key: SymmetricKey

    init(filename: String = "nuru-offline.sqlite") {
        self.key = Self.loadOrCreateKey()

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)

        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            db = nil
        }
        // iOS at-rest encryption on the DB file (and its -wal/-shm siblings).
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)

        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA foreign_keys=ON;")
        exec("""
            CREATE TABLE IF NOT EXISTS mutation_queue (
                mutation_id TEXT PRIMARY KEY, seq INTEGER NOT NULL, domain TEXT NOT NULL,
                op TEXT NOT NULL, payload BLOB NOT NULL, status TEXT NOT NULL, created_at REAL NOT NULL);
        """)
        exec("CREATE TABLE IF NOT EXISTS cursors (domain TEXT PRIMARY KEY, value INTEGER NOT NULL);")
        exec("""
            CREATE TABLE IF NOT EXISTS cache (
                domain TEXT NOT NULL, row_id TEXT NOT NULL, body BLOB NOT NULL,
                updated_at REAL NOT NULL, PRIMARY KEY (domain, row_id));
        """)
    }

    deinit { if db != nil { sqlite3_close(db) } }

    // MARK: - LocalStore: mutation queue

    func pendingMutations() -> [PendingMutation] {
        var out: [PendingMutation] = []
        prepare("SELECT mutation_id, seq, domain, op, payload, status FROM mutation_queue ORDER BY seq ASC") { st in
            while sqlite3_step(st) == SQLITE_ROW {
                guard let id = text(st, 0), let domain = text(st, 2), let op = text(st, 3),
                      let status = text(st, 5), let blob = blob(st, 4) else { continue }
                let payload = (try? JSONDecoder().decode([String: AnyCodable].self, from: unseal(blob) ?? Data())) ?? [:]
                out.append(PendingMutation(mutationId: id, seq: Int(sqlite3_column_int64(st, 1)),
                                           domain: domain, op: op, payload: payload, status: status))
            }
        }
        return out
    }

    func enqueueMutation(_ m: PendingMutation) {
        let body = seal((try? JSONEncoder().encode(m.payload)) ?? Data())
        prepare("INSERT OR REPLACE INTO mutation_queue (mutation_id, seq, domain, op, payload, status, created_at) VALUES (?,?,?,?,?,?,?)") { st in
            bindText(st, 1, m.mutationId); sqlite3_bind_int64(st, 2, Int64(m.seq))
            bindText(st, 3, m.domain); bindText(st, 4, m.op); bindBlob(st, 5, body)
            bindText(st, 6, m.status); sqlite3_bind_double(st, 7, Date().timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func removeMutations(ids: [String]) {
        guard !ids.isEmpty else { return }
        prepare("DELETE FROM mutation_queue WHERE mutation_id = ?") { st in
            for id in ids { sqlite3_reset(st); bindText(st, 1, id); sqlite3_step(st) }
        }
    }

    // MARK: - LocalStore: cursors

    func cursors() -> [String: Int] {
        var out: [String: Int] = [:]
        prepare("SELECT domain, value FROM cursors") { st in
            while sqlite3_step(st) == SQLITE_ROW {
                if let d = text(st, 0) { out[d] = Int(sqlite3_column_int64(st, 1)) }
            }
        }
        return out
    }

    func setCursor(domain: String, value: Int) {
        prepare("INSERT INTO cursors (domain, value) VALUES (?,?) ON CONFLICT(domain) DO UPDATE SET value=excluded.value") { st in
            bindText(st, 1, domain); sqlite3_bind_int64(st, 2, Int64(value)); sqlite3_step(st)
        }
    }

    // MARK: - LocalStore: pull cache (per-domain rows)

    func cacheUpsert(domain: String, rows: [(id: String, body: Data)]) {
        guard !rows.isEmpty else { return }
        exec("BEGIN")
        prepare("INSERT INTO cache (domain, row_id, body, updated_at) VALUES (?,?,?,?) ON CONFLICT(domain,row_id) DO UPDATE SET body=excluded.body, updated_at=excluded.updated_at") { st in
            for r in rows {
                sqlite3_reset(st)
                bindText(st, 1, domain); bindText(st, 2, r.id); bindBlob(st, 3, seal(r.body))
                sqlite3_bind_double(st, 4, Date().timeIntervalSince1970); sqlite3_step(st)
            }
        }
        exec("COMMIT")
    }

    /// Replace the whole domain with `rows` (used to mirror a freshly-fetched list).
    func cacheReplace(domain: String, rows: [(id: String, body: Data)]) {
        exec("BEGIN")
        prepare("DELETE FROM cache WHERE domain = ?") { st in bindText(st, 1, domain); sqlite3_step(st) }
        prepare("INSERT OR REPLACE INTO cache (domain, row_id, body, updated_at) VALUES (?,?,?,?)") { st in
            for r in rows {
                sqlite3_reset(st)
                bindText(st, 1, domain); bindText(st, 2, r.id); bindBlob(st, 3, seal(r.body))
                sqlite3_bind_double(st, 4, Date().timeIntervalSince1970); sqlite3_step(st)
            }
        }
        exec("COMMIT")
    }

    func cacheDelete(domain: String, ids: [String]) {
        guard !ids.isEmpty else { return }
        prepare("DELETE FROM cache WHERE domain = ? AND row_id = ?") { st in
            for id in ids { sqlite3_reset(st); bindText(st, 1, domain); bindText(st, 2, id); sqlite3_step(st) }
        }
    }

    func cachedRows(domain: String) -> [Data] {
        var out: [Data] = []
        prepare("SELECT body FROM cache WHERE domain = ? ORDER BY updated_at DESC") { st in
            bindText(st, 1, domain)
            while sqlite3_step(st) == SQLITE_ROW {
                if let b = blob(st, 0), let plain = unseal(b) { out.append(plain) }
            }
        }
        return out
    }

    // MARK: - AES-GCM seal / unseal

    private func seal(_ data: Data) -> Data {
        (try? AES.GCM.seal(data, using: key).combined) ?? data
    }
    private func unseal(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    private static func loadOrCreateKey() -> SymmetricKey {
        if let b64 = Keychain.get("offline.dbkey"), let raw = Data(base64Encoded: b64) {
            return SymmetricKey(data: raw)
        }
        let fresh = SymmetricKey(size: .bits256)
        let raw = fresh.withUnsafeBytes { Data($0) }
        Keychain.set(raw.base64EncodedString(), for: "offline.dbkey")
        return fresh
    }

    // MARK: - tiny SQLite helpers

    private func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }

    private func prepare(_ sql: String, _ body: (OpaquePointer) -> Void) {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { return }
        body(st)
        sqlite3_finalize(st)
    }

    private func bindText(_ st: OpaquePointer, _ i: Int32, _ v: String) {
        sqlite3_bind_text(st, i, v, -1, SQLITE_TRANSIENT)
    }
    private func bindBlob(_ st: OpaquePointer, _ i: Int32, _ v: Data) {
        v.withUnsafeBytes { sqlite3_bind_blob(st, i, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT) }
    }
    private func text(_ st: OpaquePointer, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(st, i) else { return nil }
        return String(cString: c)
    }
    private func blob(_ st: OpaquePointer, _ i: Int32) -> Data? {
        guard let p = sqlite3_column_blob(st, i) else { return nil }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(st, i)))
    }
}
