// The member's answers, saved as they go.
//
// Owner, 2026-09-15: "For every question you submit, make sure it's saved and
// in case you refresh in the middle, you go back to the question you had
// submitted and not from the beginning."
//
// Before this, answers lived in the view model and were sent all at once at
// the end. A relaunch, a low-memory kill, or a refresh lost every answer and
// put the member back on question 1. Now every answer is written here the
// moment it is given.
//
// WHY THE DRAFT STORES THE MEMBER'S QUESTION ORDER. The server assembles each
// quiz from the whole active bank in `ORDER BY random()` with shuffled
// choices, so a fresh fetch returns the same QUESTIONS in a different order.
// The draft keeps the ids in the order the member saw them; on resume the
// fresh set is reordered to match, so "question 4" is the same question. If
// the bank itself changed (an id added or removed), the draft is discarded —
// an answer to a question that no longer exists is worth nothing.
//
// WHAT THIS IS NOT. It is not a verdict. Scoring stays server-authoritative
// (§1.1): the draft holds answers only, and is cleared the moment a submit
// succeeds. Device-local by design — "refresh" is a device event; a cross-phone
// draft was neither asked for nor worth a new server contract.
//
// Files live in Application Support with `completeUntilFirstUserAuthentication`
// protection, the same class the encrypted offline store uses: the answers are
// the member's own and should not be readable off a locked, unbooted device.
import Foundation

struct QuizDraft: Codable, Sendable {
    /// "module:<id>" | "level:<n>" — one draft per test.
    let key: String
    /// Question ids in the order the member saw them.
    let questionIds: [String]
    /// Where they were.
    let index: Int
    /// single-choice id / scale number / free text, by questionId.
    let text: [String: String]
    /// checkbox selections, by questionId.
    let checks: [String: Set<String>]
    let savedAt: Date

    var answeredCount: Int { text.count + checks.values.filter { !$0.isEmpty }.count }
}

/// The gifts assessment has a different question shape and a set id; its set is
/// already Codable, so the draft carries the whole set and never refetches.
struct GiftsDraft: Codable, Sendable {
    let questionSet: GiftQuestionSet
    let chosen: [String: Int]
    let step: Int
    let savedAt: Date
}

enum QuizDraftStore {
    /// Drafts older than this are stale — the member has moved on.
    private static let maxAge: TimeInterval = 14 * 24 * 60 * 60
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("QuizDrafts", isDirectory: true)
    }

    private static func url(_ key: String) -> URL {
        // Keys carry ":" — safe on APFS, but keep filenames plain regardless.
        dir.appendingPathComponent(key.replacingOccurrences(of: ":", with: "_") + ".json")
    }

    // MARK: - Quizzes and exams

    static func load(_ key: String) -> QuizDraft? {
        guard let data = try? Data(contentsOf: url(key)),
              let d = try? decoder.decode(QuizDraft.self, from: data) else {
            clear(key); return nil            // unreadable = discard, never crash
        }
        guard Date().timeIntervalSince(d.savedAt) < maxAge, !d.questionIds.isEmpty else {
            clear(key); return nil
        }
        return d
    }

    /// Called on EVERY answer and every question change. Cheap: one small file.
    static func save(_ key: String, questionIds: [String], index: Int,
                     text: [String: String], checks: [String: Set<String>]) {
        let d = QuizDraft(key: key, questionIds: questionIds, index: index,
                          text: text, checks: checks, savedAt: Date())
        write(d, to: url(key))
    }

    /// On a successful submit, or an explicit "start over".
    static func clear(_ key: String) {
        try? FileManager.default.removeItem(at: url(key))
    }

    /// Reorder a freshly fetched set into the draft's order. Returns nil when the
    /// bank changed — then the draft is discarded by the caller.
    static func reorder(_ fresh: [QuizQuestion], to draft: QuizDraft) -> [QuizQuestion]? {
        guard Set(fresh.map(\.questionId)) == Set(draft.questionIds) else { return nil }
        let byId = Dictionary(uniqueKeysWithValues: fresh.map { ($0.questionId, $0) })
        return draft.questionIds.compactMap { byId[$0] }
    }

    // MARK: - Gifts assessment

    private static let giftsKey = "gifts"

    static func loadGifts() -> GiftsDraft? {
        guard let data = try? Data(contentsOf: url(giftsKey)),
              let d = try? decoder.decode(GiftsDraft.self, from: data) else {
            clearGifts(); return nil
        }
        guard Date().timeIntervalSince(d.savedAt) < maxAge, !d.questionSet.data.isEmpty else {
            clearGifts(); return nil
        }
        return d
    }

    static func saveGifts(_ set: GiftQuestionSet, chosen: [String: Int], step: Int) {
        write(GiftsDraft(questionSet: set, chosen: chosen, step: step, savedAt: Date()), to: url(giftsKey))
    }

    static func clearGifts() {
        try? FileManager.default.removeItem(at: url(giftsKey))
    }

    // MARK: - Disk

    private static func write<T: Encodable>(_ value: T, to file: URL) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try encoder.encode(value)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // A failed save must never interrupt a member mid-quiz. They keep
            // answering; the next answer tries again.
        }
    }
}
