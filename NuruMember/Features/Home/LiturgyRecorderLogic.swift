// Liturgy recorder — PURE logic only (no AVFoundation, no SwiftUI): the
// admin-only "which bands have his voice" list and the small arithmetic
// around a take's length. Kept separate from LiturgyRecorder.swift (the
// AVAudioRecorder-backed model + sheets) exactly the way LiturgyVoiceLogic.swift
// is kept separate from LiturgyVoice.swift — so every rule here is testable
// on any platform, with no simulator/device audio stack.
//
// Design constraint this file exists to protect (see docs/COORDINATED_DEV.md
// task brief): seven bands a day is 49 recordings a week — nobody sustains
// that. Mixed coverage is the PERMANENT NORMAL state, not a gap. Nothing here
// counts "how many are done" or ranks bands by urgency — `LiturgyRecordingRow`
// is a flat, unordered-by-completeness list, always in the same clock order,
// so the pastor sees his own coverage the way he'd see a clock face, not a
// checklist.
import Foundation

// MARK: - The 7 bands

enum LiturgyBand: String, CaseIterable, Equatable {
    case sunrise, morning, midday, afternoon, evening, night, midnight

    /// Clock order — mirrors exactly what `GET admin/liturgy/recordings`
    /// always returns (7 rows, this order). The recorder list renders in
    /// this same order so "which hours are covered" reads like the day.
    static let clockOrder: [LiturgyBand] = [.sunrise, .morning, .midday, .afternoon, .evening, .night, .midnight]

    var label: String {
        switch self {
        case .sunrise: return "Sunrise"
        case .morning: return "Morning"
        case .midday: return "Midday"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .night: return "Night"
        case .midnight: return "Midnight"
        }
    }
}

// MARK: - One row in the recorder list

/// A band plus whatever the server told us about it. `audioUrl == nil` means
/// synthesis covers this band right now — the normal state for most rows,
/// most of the time — never rendered as "missing" or an error.
struct LiturgyRecordingRow: Identifiable, Equatable {
    let band: LiturgyBand
    let audioUrl: String?
    let durationSec: Int?
    var id: String { band.rawValue }
    var hasRecording: Bool { (audioUrl?.isEmpty ?? true) == false }
}

enum LiturgyRecordingRows {
    /// Builds the full, canonically clock-ordered 7-row list from whatever
    /// the server sent. The contract guarantees exactly 7 rows already in
    /// this order, but this stays defensive the same way every other list in
    /// this app is (HomeLiturgy, CommunityMoment, …): a short, reordered, or
    /// duplicated response still degrades to a complete, correctly-ordered
    /// list rather than a stale or malformed one. A duplicate band entry
    /// keeps the LAST one (mirrors "an upsert replaces" semantics); an
    /// unrecognized band string is dropped rather than crashing the list.
    static func build(from statuses: [LiturgyRecordingStatus]) -> [LiturgyRecordingRow] {
        var byBand: [String: LiturgyRecordingStatus] = [:]
        for s in statuses { byBand[s.band] = s }
        return LiturgyBand.clockOrder.map { band in
            let s = byBand[band.rawValue]
            return LiturgyRecordingRow(band: band, audioUrl: s?.audioUrl, durationSec: s?.durationSec)
        }
    }
}

// MARK: - Duration

/// "3:07" / "0:45" — mm:ss for a recorded take's length. Pure so the actual
/// wording is provable without AVAudioRecorder.
enum LiturgyRecorderFormat {
    static func timeString(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}

/// The backend's own bound (`duration_sec`, 1–900 inclusive — up to 15
/// minutes). Checked client-side too so a bad take never round-trips to the
/// server only to bounce on validation.
enum LiturgyRecorderValidation {
    static func isValidDuration(_ seconds: Int) -> Bool { (1...900).contains(seconds) }
}
