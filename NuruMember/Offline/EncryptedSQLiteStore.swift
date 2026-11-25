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
    // `nonisolated(unsafe)` because the low-level SQLite helpers below are
    // `nonisolated` (so `init` can create the tables without a Swift-6 actor
    // violation). Concurrency is safe: the connection is opened with
    // SQLITE_OPEN_FULLMUTEX, so SQLite serializes access internally.
    nonisolated(unsafe) private var db: OpaquePointer?
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
        // The WAL sidecars hold the same sensitive pages as the main DB; the
        // CREATE TABLEs above materialize them, so stamp the protection class
        // here too (best-effort — the directory default already matches).
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path + suffix)
        }
    }

    deinit { if db != nil { sqlite3_close(db) } }

    // MARK: - LocalStore: mutation queue

    enum QueueReadError: Error { case unreadable }

    func pendingMutations() throws -> [PendingMutation] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT mutation_id, seq, domain, op, payload, status FROM mutation_queue ORDER BY seq ASC", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw QueueReadError.unreadable }
        defer { sqlite3_finalize(statement) }
        var out: [PendingMutation] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return out }
            guard result == SQLITE_ROW,
                  let id = text(statement, 0), let domain = text(statement, 2), let op = text(statement, 3),
                  let status = text(statement, 5), let data = blob(statement, 4),
                  let plain = unseal(data),
                  let payload = try? JSONDecoder().decode([String: AnyCodable].self, from: plain)
            else { throw QueueReadError.unreadable }
            out.append(PendingMutation(mutationId: id, seq: Int(sqlite3_column_int64(statement, 1)),
                                       domain: domain, op: op, payload: payload, status: status))
        }
    }

    enum QueueWriteError: Error { case encryptionFailed, storageFailed }

    func enqueueMutation(_ m: PendingMutation) throws {
        let plain = try JSONEncoder().encode(m.payload)
        guard let body = try AES.GCM.seal(plain, using: key).combined else { throw QueueWriteError.encryptionFailed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO mutation_queue (mutation_id, seq, domain, op, payload, status, created_at) VALUES (?,?,?,?,?,?,?)", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw QueueWriteError.storageFailed }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, m.mutationId); sqlite3_bind_int64(statement, 2, Int64(m.seq))
        bindText(statement, 3, m.domain); bindText(statement, 4, m.op); bindBlob(statement, 5, body)
        bindText(statement, 6, m.status); sqlite3_bind_double(statement, 7, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw QueueWriteError.storageFailed }
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

    enum CacheWriteError: Error { case encryptionFailed, databaseFailed }

    private func checkedStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw CacheWriteError.databaseFailed }
        defer { sqlite3_finalize(statement) }
        try body(statement)
    }

    private func checkedExec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CacheWriteError.databaseFailed }
    }

    func setCursor(domain: String, value: Int) throws {
        try checkedStatement("INSERT INTO cursors (domain, value) VALUES (?,?) ON CONFLICT(domain) DO UPDATE SET value=excluded.value") { st in
            bindText(st, 1, domain); sqlite3_bind_int64(st, 2, Int64(value))
            guard sqlite3_step(st) == SQLITE_DONE else { throw CacheWriteError.databaseFailed }
        }
    }

    private func writeCache(domain: String, rows: [(id: String, body: Data)], replace: Bool) throws {
        // Encrypt all rows before touching the database: never persist plaintext
        // or delete the old cache if encryption cannot complete.
        let encrypted = try rows.map { row -> (String, Data) in
            guard let sealed = try AES.GCM.seal(row.body, using: key).combined else { throw CacheWriteError.encryptionFailed }
            return (row.id, sealed)
        }
        try checkedExec("BEGIN")
        do {
            if replace {
                try checkedStatement("DELETE FROM cache WHERE domain = ?") { st in
                    bindText(st, 1, domain)
                    guard sqlite3_step(st) == SQLITE_DONE else { throw CacheWriteError.databaseFailed }
                }
            }
            try checkedStatement("INSERT INTO cache (domain, row_id, body, updated_at) VALUES (?,?,?,?) ON CONFLICT(domain,row_id) DO UPDATE SET body=excluded.body, updated_at=excluded.updated_at") { st in
                for (id, body) in encrypted {
                    sqlite3_reset(st); sqlite3_clear_bindings(st)
                    bindText(st, 1, domain); bindText(st, 2, id); bindBlob(st, 3, body)
                    sqlite3_bind_double(st, 4, Date().timeIntervalSince1970)
                    guard sqlite3_step(st) == SQLITE_DONE else { throw CacheWriteError.databaseFailed }
                }
            }
            try checkedExec("COMMIT")
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    func cacheUpsert(domain: String, rows: [(id: String, body: Data)]) throws {
        guard !rows.isEmpty else { return }
        try writeCache(domain: domain, rows: rows, replace: false)
    }

    func cacheReplace(domain: String, rows: [(id: String, body: Data)]) throws {
        try writeCache(domain: domain, rows: rows, replace: true)
    }

    func cacheDelete(domain: String, ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try checkedExec("BEGIN")
        do {
            try checkedStatement("DELETE FROM cache WHERE domain = ? AND row_id = ?") { st in
                for id in ids {
                    sqlite3_reset(st); sqlite3_clear_bindings(st)
                    bindText(st, 1, domain); bindText(st, 2, id)
                    guard sqlite3_step(st) == SQLITE_DONE else { throw CacheWriteError.databaseFailed }
                }
            }
            try checkedExec("COMMIT")
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
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

    nonisolated private func unseal(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    private static func loadOrCreateKey() -> SymmetricKey {
        if let b64 = Keychain.get("offline.dbkey"), let raw = Data(base64Encoded: b64) {
            // Re-write on load so a key created before the ThisDeviceOnly
            // hardening picks up the stricter Keychain class (set() = delete+re-add).
            Keychain.set(b64, for: "offline.dbkey")
            return SymmetricKey(data: raw)
        }
        let fresh = SymmetricKey(size: .bits256)
        let raw = fresh.withUnsafeBytes { Data($0) }
        Keychain.set(raw.base64EncodedString(), for: "offline.dbkey")
        return fresh
    }

    // MARK: - tiny SQLite helpers

    nonisolated private func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }

    nonisolated private func prepare(_ sql: String, _ body: (OpaquePointer) -> Void) {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { return }
        body(st)
        sqlite3_finalize(st)
    }

    nonisolated private func bindText(_ st: OpaquePointer, _ i: Int32, _ v: String) {
        sqlite3_bind_text(st, i, v, -1, SQLITE_TRANSIENT)
    }
    nonisolated private func bindBlob(_ st: OpaquePointer, _ i: Int32, _ v: Data) {
        _ = v.withUnsafeBytes { sqlite3_bind_blob(st, i, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT) }
    }
    nonisolated private func text(_ st: OpaquePointer, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(st, i) else { return nil }
        return String(cString: c)
    }
    nonisolated private func blob(_ st: OpaquePointer, _ i: Int32) -> Data? {
        guard let p = sqlite3_column_blob(st, i) else { return nil }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(st, i)))
    }
}
