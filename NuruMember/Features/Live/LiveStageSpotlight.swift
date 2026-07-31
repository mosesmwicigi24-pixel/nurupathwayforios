// Nuru Live — pure Zoom-style spotlight state machine. Host (track 0) is
// the default main tile. Tapping a guest's rail thumbnail promotes them to
// main and demotes whoever was main into the rail; tapping the CURRENT
// main tile again reverts to host (exactly Zoom's "tap to unpin"). A
// spotlighted guest leaving the stage falls back to host automatically —
// the compositor must never be left pointed at a torn-down track.
//
// Pure value type, no HaishinKit/SwiftUI import — both LiveStageCompositor
// and BroadcastController (which drives the SwiftUI stage) hold their own
// copy and stay in lockstep by construction, not by convention.
struct LiveStageSpotlight: Equatable {
    /// Host is always track 0 — see BroadcastController's track allocation
    /// (guests are 1...6).
    static let host: UInt8 = 0

    private(set) var spotlighted: UInt8 = Self.host

    /// Tapping any tile:
    /// - the currently-spotlighted GUEST tapped again → reverts to host.
    /// - host's own tile tapped while host is ALREADY main → no-op
    ///   (nothing to revert to).
    /// - anything else (a rail thumbnail — host's or another guest's) →
    ///   becomes the new spotlight, demoting whoever was main into the rail.
    mutating func tap(_ track: UInt8) {
        if track == spotlighted {
            guard track != Self.host else { return }
            spotlighted = Self.host
        } else {
            spotlighted = track
        }
    }

    /// A participant left the stage. If they were spotlighted, fall back to
    /// host; otherwise a no-op (they were already just a rail tile, nothing
    /// about the spotlight changes).
    mutating func participantLeft(_ track: UInt8) {
        guard spotlighted == track else { return }
        spotlighted = Self.host
    }

    /// Forces back to host — used when Document/Screen source takes over:
    /// the shared surface is always the big tile, independent of who was
    /// spotlighted on camera before the switch.
    mutating func reset() {
        spotlighted = Self.host
    }
}
