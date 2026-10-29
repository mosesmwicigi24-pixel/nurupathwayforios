// The words on a department's notification — the server's push copy
// (workers/dispatch.ts PUSH_TEMPLATE_COPY, docs/PARTNERS_PROGRAMME.md §4), so
// the inbox row, the banner and Android say what the push said. Before this
// the inbox had a title of its own and no line for a member's serve request
// or a department post, and nothing at all for the leader's
// serve_request_received (audit, 2026-09-28).
import Foundation

/// The push's words for serve_request_* and department_post; nil for any
/// other template (the caller's own fallback applies — department_need_* are a
/// giving target and are not worded here). Callers check the payload's own
/// `title` / `body` first, as dispatch.ts pushCopy() does; these payloads
/// carry neither.
enum DepartmentNotificationCopy {
    static func title(template: String, payload: NotifPayload?) -> String? {
        let department = said(payload?.department)
        switch template {
        // To the department's LEADER; `name` is the member who asked.
        case "serve_request_received": return "\(said(payload?.name) ?? "Someone") wants to serve in \(department ?? "your department")"
        case "serve_request_approved": return "Welcome to \(department ?? "the department")"
        case "serve_request_declined": return "About \(department ?? "the department")"
        case "department_post": return department ?? "Your department"
        default: return nil
        }
    }

    static func body(template: String, payload: NotifPayload?) -> String? {
        switch template {
        case "serve_request_received": return "Open the portal to welcome them in."
        case "serve_request_approved": return "Your request to serve was approved. Open Departments to see what's next."
        case "serve_request_declined": return "The leader couldn't take you on right now. Other departments would love your hands — open Departments."
        case "department_post": return said(payload?.preview) ?? "A new post from your department."
        default: return nil
        }
    }

    /// dispatch.ts `str`: a non-empty string exactly as sent (not trimmed), else nil.
    private static func said(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
