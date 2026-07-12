// Discipleship Hub — the student-facing aggregation of "where am I, who is my
// discipler, what am I waiting on" served by GET /me/discipleship. Pure read
// (no side effects). The APIClient converts snake_case ⇆ camelCase, so every
// property here is camelCase; everything the wire may omit is a tolerant optional
// so a sparse payload (no discipler yet, uncomputed scores) still decodes.
import Foundation

/// The whole `{ data: … }` payload for the member's Discipleship Hub.
struct Discipleship: Codable, Sendable {
    /// The resolved discipler (explicit relationship edge, else the cell leader).
    /// `nil` when the member hasn't been paired yet — the Hub shows a warm empty state.
    let discipler: Discipler?
    /// Present only when a 1:1 DM already exists (a GET never creates one); the
    /// hero CTA opens it directly. When nil the CTA creates it via POST /chat/dms.
    let dmConversationId: String?
    /// False for minors — chat is blocked, so the Hub replaces the message CTA
    /// with a gentle "talk in your cell gathering" note.
    let canMessage: Bool
    let progression: Progression
    let scores: HubScores
    /// The member's own reflections, most-recent first (server caps at 20).
    let reflections: [HubReflection]
    let nextMeetingAt: String?
    let notes: [HubNote]

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        discipler = try? c.decodeIfPresent(Discipler.self, forKey: .discipler)
        dmConversationId = try? c.decodeIfPresent(String.self, forKey: .dmConversationId)
        canMessage = (try? c.decodeIfPresent(Bool.self, forKey: .canMessage)) ?? false
        progression = (try? c.decodeIfPresent(Progression.self, forKey: .progression))
            ?? Progression(currentLevel: 1, levelTitle: "", streakDays: 0, modulesCompleted: 0,
                           modulesTotal: 0, awaitingReview: false, awaitingLevel: nil)
        scores = (try? c.decodeIfPresent(HubScores.self, forKey: .scores))
            ?? HubScores(overall: nil, word: nil, prayer: nil, habits: nil,
                         curriculum: nil, attendance: nil)
        reflections = (try? c.decodeIfPresent([HubReflection].self, forKey: .reflections)) ?? []
        nextMeetingAt = try? c.decodeIfPresent(String.self, forKey: .nextMeetingAt)
        notes = (try? c.decodeIfPresent([HubNote].self, forKey: .notes)) ?? []
    }

    /// The resolved discipler card.
    struct Discipler: Codable, Sendable {
        let userId: String
        let fullName: String
        let avatarUrl: String?
        let roleLabel: String
        let cellName: String?
        let establishedAt: String?
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
            fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
            avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
            roleLabel = (try? c.decodeIfPresent(String.self, forKey: .roleLabel)) ?? ""
            cellName = try? c.decodeIfPresent(String.self, forKey: .cellName)
            establishedAt = try? c.decodeIfPresent(String.self, forKey: .establishedAt)
        }
    }

    /// Where the member is on the pathway (server-authoritative — the Hub only
    /// reflects it, never advances anything, §1.9).
    struct Progression: Codable, Sendable {
        let currentLevel: Int
        let levelTitle: String
        let streakDays: Int
        let modulesCompleted: Int
        let modulesTotal: Int
        /// A pending level_advancement exists — the member is awaiting a discipler's usher.
        let awaitingReview: Bool
        /// The level number awaiting usher, or nil.
        let awaitingLevel: Int?
    }

    /// The six growth scores (0..100), each nil until computed.
    struct HubScores: Codable, Sendable {
        let overall: Int?
        let word: Int?
        let prayer: Int?
        let habits: Int?
        let curriculum: Int?
        let attendance: Int?
    }

    /// One of the member's reflections + the discipler's feedback (never the
    /// private pastoral note — the backend already withholds that from members).
    struct HubReflection: Codable, Sendable, Identifiable {
        let moduleId: String
        let moduleTitle: String
        let levelNumber: Int
        /// approved | pending | returned | deferred.
        let state: String
        let submittedAt: String
        let feedbackNotes: String?

        // Stable identity for ForEach (a member can reflect on a module once,
        // so module id is unique within the list).
        var id: String { moduleId }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            moduleId = (try? c.decodeIfPresent(String.self, forKey: .moduleId)) ?? ""
            moduleTitle = (try? c.decodeIfPresent(String.self, forKey: .moduleTitle)) ?? ""
            levelNumber = (try? c.decodeIfPresent(Int.self, forKey: .levelNumber)) ?? 0
            state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? ""
            submittedAt = (try? c.decodeIfPresent(String.self, forKey: .submittedAt)) ?? ""
            feedbackNotes = try? c.decodeIfPresent(String.self, forKey: .feedbackNotes)
        }
    }

    /// A meeting note from the discipler.
    struct HubNote: Codable, Sendable {
        let topic: String
        let body: String
        let metAt: String
        let nextMeetingAt: String?
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            topic = (try? c.decodeIfPresent(String.self, forKey: .topic)) ?? ""
            body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
            metAt = (try? c.decodeIfPresent(String.self, forKey: .metAt)) ?? ""
            nextMeetingAt = try? c.decodeIfPresent(String.self, forKey: .nextMeetingAt)
        }
    }
}

// Tolerant decoding in an extension so the memberwise init stays available for
// the sparse-payload fallback above.
extension Discipleship.Progression {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        currentLevel = (try? c.decodeIfPresent(Int.self, forKey: .currentLevel)) ?? 1
        levelTitle = (try? c.decodeIfPresent(String.self, forKey: .levelTitle)) ?? ""
        streakDays = (try? c.decodeIfPresent(Int.self, forKey: .streakDays)) ?? 0
        modulesCompleted = (try? c.decodeIfPresent(Int.self, forKey: .modulesCompleted)) ?? 0
        modulesTotal = (try? c.decodeIfPresent(Int.self, forKey: .modulesTotal)) ?? 0
        awaitingReview = (try? c.decodeIfPresent(Bool.self, forKey: .awaitingReview)) ?? false
        awaitingLevel = try? c.decodeIfPresent(Int.self, forKey: .awaitingLevel)
    }
}
