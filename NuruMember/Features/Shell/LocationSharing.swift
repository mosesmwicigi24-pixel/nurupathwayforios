// Turning location sharing on or off waits for the server (owner decision,
// EXPERIENCE.md §7.4): the switch moves only when the server has the answer;
// on a failure it stays as it was and says why — "Couldn't save that." and
// the §4 sentence. Every place the member turns it — Settings' switch and
// the first-run invite — goes through here. (The silent refresh on app open,
// for a member who already said yes, stays silent: nothing is shown.)
import Foundation

enum LocationSharing {
    static let key = "nuru.privacy.shareLocation"

    enum Outcome: Equatable {
        case saved
        case failed(String)
    }

    /// Asks the server to share (with one coarse fix) or to stop; records
    /// the member's choice only once the server has said yes.
    @MainActor
    static func set(_ on: Bool, using location: LocationManager,
                    defaults: UserDefaults = .standard) async -> Outcome {
        do {
            if on {
                guard let c = await location.requestCoarseFix() else {
                    return .failed(noFixLine(denied: location.isDenied))
                }
                try await MemberAPI.shareLocation(lat: c.latitude, lng: c.longitude)
            } else {
                try await MemberAPI.stopSharingLocation()
            }
        } catch {
            return .failed(NuruStateCopy.saveFailureLine(error))
        }
        defaults.set(on, forKey: key)
        return .saved
    }

    /// No coarse fix to send: the phone's permission, or the phone itself.
    static func noFixLine(denied: Bool) -> String {
        denied
            ? "Couldn't save that. Location is off for Nuru on this phone — allow it in Settings, then try again."
            : "Couldn't save that. This phone couldn't find where it is just now — try again."
    }
}
