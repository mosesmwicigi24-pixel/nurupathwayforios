// Nuru Live — owner-directed LIVE screen redesign (2026-08-01): "the content
// gets the ENTIRE screen; everything else overlays it." Replaces the old
// three-scattered-top-rows + right-edge floating reaction rail +
// bottom-left-overlapping self-preview with:
//   - ONE top row directly under the safe area (host chip · title · LIVE ·
//     counters) — see `LiveTopStatChip` below and each screen's own
//     `topBar`/`topBadges`.
//   - ONE bottom dock (`LiveDockLayout` below) holding every control —
//     reactions, raise-hand, chat, guest stage controls (camera/mic/switch/
//     speaker/leave), the broadcaster's own controls, and the document page
//     indicator. Never floats OVER content — it sits on its own gradient
//     scrim (`LiveChromeScrim`), matching a Zoom/FaceTime-style dock.
//
// Shared by LiveViewerPlayerView (plain viewer AND an accepted guest-on-
// stage — same screen, different role) and GoLiveBroadcastView (the
// broadcaster's own Studio). Kept as ONE file specifically so "the
// broadcaster's Studio screen follows the same grammar" is true by
// construction — both screens import the same enums/views rather than
// hand-rolling their own, which is exactly how the sibling LiveStageLayout
// file keeps LiveStageCompositor and LiveStageView from independently
// drifting (see that file's own header comment).
//
// Everything in the "MARK: Pure" section below is plain data — no SwiftUI,
// no I/O, no environment reads — precisely so LiveDockChromeTests can pin
// per-role item ordering/eligibility and the self-preview collapse reducer
// without touching a view hierarchy. The view helpers further down are
// deliberately dumb (icon + optional caption + tap handler) — every screen
// still owns its OWN wiring (which API call fires, whether a control is
// disabled right now), this file only owns what the control looks like and
// which controls exist for a given role.
import SwiftUI

// MARK: Pure — dock role, item set, ordering, self-preview reducer

/// Who's looking at the dock — drives which controls are eligible at all.
/// A plain viewer never gets stage/hardware controls (no camera or mic to
/// control); an accepted guest gets the full stage-control set; the
/// broadcaster keeps their own existing control set (mic/camera-switch/End),
/// restyled into the same dock grammar rather than handed guest-only
/// affordances that would make no sense for them (see LiveDockLayout's own
/// doc comment on why "camera on/off" and "speaker" are guest-only).
enum LiveDockRole: Equatable {
    case viewer
    case guestOnStage
    case broadcaster
}

/// One control the dock can show. `Identifiable` so `ForEach` over a row
/// doesn't need a synthetic index, `Equatable` so `LiveDockLayout.rows`
/// below can partition a role's item list by membership.
enum LiveDockItem: Equatable, Identifiable {
    case reaction(LiveReactionKind)
    case raiseHand
    case chat
    /// Guest-only — toggles the GUEST's own outbound camera on/off
    /// (`WhipPublisher.toggleVideo`). Never shown to the broadcaster: pausing
    /// THEIR camera would blank the frame for every viewer, a fundamentally
    /// different (and far riskier) action than a guest's own tiny
    /// self-preview going dark — see WhipPublisher's header comment.
    case camera
    /// Front/back swap. Guest → `WhipPublisher.flipCamera()`. Broadcaster →
    /// the existing `BroadcastController.flipCamera()` (unchanged).
    case switchCamera
    case mic
    /// Guest-only — output audio route (speaker vs. earpiece), via
    /// `WhipPublisher.toggleSpeaker()`. Not offered to the broadcaster: their
    /// own mic/audio session is HaishinKit's, with no equivalent route
    /// switch on this screen today.
    case speaker
    /// A guest stepping off stage (`leaveGuestStage()`), distinct from the
    /// broadcaster's `.end` (ending the whole stream for everyone).
    case leave
    case end
    /// The broadcaster's own "Page X of Y" while sharing a document —
    /// display-only, not a button (see LiveDockLayout's own note on why a
    /// PLAIN VIEWER never gets this: BroadcastController.documentPageIndex
    /// is host-local state, never carried on the wire pulse today).
    case documentPage

    var id: String {
        switch self {
        case .reaction(let kind): return "reaction-\(kind.emoji)"
        case .raiseHand: return "raiseHand"
        case .chat: return "chat"
        case .camera: return "camera"
        case .switchCamera: return "switchCamera"
        case .mic: return "mic"
        case .speaker: return "speaker"
        case .leave: return "leave"
        case .end: return "end"
        case .documentPage: return "documentPage"
        }
    }
}

/// Pure per-role eligibility + ordering — the same list, in the same order,
/// every time for a given (role, isVideo, hasDocumentPage) input. No view,
/// no state, no I/O. See LiveDockChromeTests for the pinned contract this
/// guards (owner spec: "EVERY control lives there").
enum LiveDockLayout {
    /// `isVideo` only matters for `.broadcaster` (an audio-only broadcast has
    /// no camera to switch — mirrors GoLiveBroadcastView's existing
    /// `if controller.isVideo { flip } else { spacer }` branch). A guest is
    /// ALWAYS on camera (WhipPublisher always captures one), so `.guestOnStage`
    /// ignores the flag entirely rather than silently no-op-ing on it.
    static func items(role: LiveDockRole, isVideo: Bool = true, hasDocumentPage: Bool = false) -> [LiveDockItem] {
        switch role {
        case .viewer:
            return [.reaction(.love), .reaction(.fire), .reaction(.like), .raiseHand, .chat]
        case .guestOnStage:
            return [.reaction(.love), .reaction(.fire), .reaction(.like), .raiseHand, .chat,
                    .camera, .switchCamera, .mic, .speaker, .leave]
        case .broadcaster:
            var out: [LiveDockItem] = [.mic]
            if isVideo { out.append(.switchCamera) }
            out.append(.end)
            out.append(.raiseHand)
            out.append(.chat)
            if hasDocumentPage { out.append(.documentPage) }
            return out
        }
    }

    /// Splits a role's items into visual rows so a wide set (guest-on-stage:
    /// up to 10 controls) never has to shrink tap targets below the 44pt
    /// minimum to fit one line. `.viewer` and `.broadcaster` top out at 5-6
    /// items and always fit a single row; `.guestOnStage` splits into
    /// "engagement" (reactions/raise-hand/chat — what any viewer already
    /// has) on top and "stage hardware" (camera/switch/mic/speaker/leave) on
    /// the row below, so the two concerns read as distinct clusters within
    /// the ONE dock container rather than one undifferentiated wall of icons.
    static func rows(role: LiveDockRole, isVideo: Bool = true, hasDocumentPage: Bool = false) -> [[LiveDockItem]] {
        let all = items(role: role, isVideo: isVideo, hasDocumentPage: hasDocumentPage)
        guard role == .guestOnStage else { return [all] }
        let engagementIds: Set<String> = [
            LiveDockItem.reaction(.love).id, LiveDockItem.reaction(.fire).id, LiveDockItem.reaction(.like).id,
            LiveDockItem.raiseHand.id, LiveDockItem.chat.id
        ]
        let engagement = all.filter { engagementIds.contains($0.id) }
        let stage = all.filter { !engagementIds.contains($0.id) }
        return [engagement, stage]
    }
}

/// Pure reducer behind GuestStagePiP's minimize/restore pill (owner spec:
/// "must be minimizable ... collapses to a small pill/handle, tap to
/// restore, state remembered within the session"). `.stageBecameActive`
/// exists so a FRESH stage window (accepted → left → re-accepted, or a
/// brand-new stream) always starts back at `.expanded` — a member landing on
/// stage should never find their own preview silently collapsed from a
/// previous session with no idea why.
enum GuestPreviewVisibility: Equatable {
    case expanded
    case collapsed

    enum Event { case toggle, stageBecameActive }

    func reduce(_ event: Event) -> GuestPreviewVisibility {
        switch event {
        case .toggle: return self == .expanded ? .collapsed : .expanded
        case .stageBecameActive: return .expanded
        }
    }
}

// MARK: - Shared view atoms — icon button, danger/text button, top-bar stat chip, scrims

/// One dock control: 44x44pt circle (tap-target floor, owner spec), an
/// optional caption underneath (reaction counts), gold fill when `active`.
/// Every screen wires its OWN action/state — this view only knows how to
/// look and announce itself.
struct LiveDockIconButton: View {
    let systemImage: String
    var active: Bool = false
    var caption: String? = nil
    var disabled: Bool = false
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(active ? Nuru.navy : .white)
                    .frame(width: 44, height: 44)
                    .background(active ? Nuru.gold : Color.white.opacity(0.14), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                if let caption {
                    Text(caption).font(.inter(10, .semibold)).foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
            }
        }
        .buttonStyle(.pressable)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The one text-labeled control in the dock (Leave stage / End) — kept
/// wider + labeled (not icon-only) since it's the single irreversible
/// action in the row and deserves to read unambiguously at a glance, same
/// idiom GoLiveBroadcastView's "End" pill already used pre-redesign.
struct LiveDockDangerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.inter(13, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 44)
                .background(Color(hex: 0xDC2626), in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}

/// A compact top-row counter ("👁 1.2K", "✋ 3") — small enough that host
/// chip + title + LIVE pill + a couple of these all fit on ONE line (owner
/// spec item 2).
struct LiveTopStatChip: View {
    let systemImage: String
    let value: String
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 10)).foregroundStyle(tint.opacity(0.9))
            Text(value).font(.inter(10, .semibold)).foregroundStyle(tint.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.black.opacity(0.4), in: Capsule())
    }
}

/// Full-bleed gradient scrims behind the top row / bottom dock — "subtle
/// gradient scrims so white content stays readable beneath, no heavy opaque
/// bars" (owner spec). Deliberately `.ignoresSafeArea` on JUST the gradient
/// shape, never on the row of controls sitting in front of it — that's what
/// lets the dark wash reach the true screen edge while every button/label
/// still lands safely clear of the Dynamic Island / home indicator, using
/// SwiftUI's own default safe-area layout rather than hand-rolled insets.
enum LiveChromeScrim {
    static func top(height: CGFloat = 130) -> some View {
        LinearGradient(colors: [.black.opacity(0.62), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    static func bottom(height: CGFloat = 220) -> some View {
        LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
    }
}
