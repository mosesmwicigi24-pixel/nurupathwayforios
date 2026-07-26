// Nuru Live L3 — client-side gating for the "Go Live" entry points. This is
// ADVISORY ONLY: packages/backend/src/modules/live/service.ts is the actual
// authority and re-checks everything on POST /live/streams regardless
// (403 FORBIDDEN_SCOPE). This file exists so a member is never SHOWN a scope
// they'd then be refused for.
//
// Church-scope eligibility mirrors the backend's own staff check exactly:
// `LiveService.isStaff()` accepts `IdentityService.STAFF_ROLES` (Instructor,
// Admin, SuperAdmin) OR a `users.is_staff` column this DTO doesn't carry. The
// STAFF_ROLES set is also the exact set ModuleView.swift already uses
// client-side ("may grade/teach" gating) — same rule, same source of truth,
// reused rather than re-invented. The `is_staff`-only case (staff flagged
// solely via that column, no STAFF_ROLES role) is the one accepted false
// NEGATIVE here: that member simply won't see "Church" in the picker even
// though the server would allow it. A false POSITIVE never happens — this
// rule is always a subset of the server's, so nobody sees a scope option
// that then 403s.
enum LiveBroadcastEligibility {
    static let staffRoles: Set<String> = ["Instructor", "Admin", "SuperAdmin"]

    /// Show ANY "Go Live" affordance at all (Home header icon, cell button).
    static func canGoLive(_ profile: UserProfile?) -> Bool {
        profile?.permissions.contains("live:go") == true
    }

    /// Offer the "Church" scope in the setup sheet.
    static func churchEligible(_ profile: UserProfile?) -> Bool {
        guard let profile else { return false }
        return staffRoles.contains(profile.role)
    }

    /// Offer the "My cell" scope in the setup sheet — and, per the documented
    /// simplification below, whether CellInfoView's Go Live button shows at
    /// all.
    static func cellEligible(_ profile: UserProfile?) -> Bool {
        profile?.cellGroupId?.isEmpty == false
    }

    /// CellInfoView's Go Live button: only when the member both holds the
    /// permission AND has a cell of their own — a `live:go` staff member with
    /// no cell still reaches broadcasting via Home's Church entry point, so
    /// hiding the cell button for them loses nothing.
    static func showCellEntryPoint(_ profile: UserProfile?) -> Bool {
        canGoLive(profile) && cellEligible(profile)
    }
}
