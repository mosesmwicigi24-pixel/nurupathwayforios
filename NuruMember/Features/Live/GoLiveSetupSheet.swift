// Nuru Live L3 — the "Go Live" setup sheet, presented as a `.sheet` from
// either Home's header icon (church/cell picker) or CellInfoView's Go Live
// button (forced scope=cell). Collects title/kind/scope, requests camera+mic
// permission UP FRONT — before ever calling POST /live/streams, so a hard
// denial never mints an orphaned "live" row with nothing publishing to it —
// then starts the stream and hands the result to the caller, which presents
// GoLiveBroadcastView.
import SwiftUI
import UIKit

struct GoLiveSetupSheet: View {
    /// nil → offer whatever scopes the signed-in profile is eligible for
    /// (Home entry point). Non-nil → force scope=cell to this exact cell,
    /// no picker shown at all (CellInfoView entry point).
    let forcedCell: (id: String, name: String)?
    let onStarted: (GoLiveSession) -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var kind: LiveBroadcastKind = .video
    @State private var scope: LiveBroadcastScopeChoice
    @State private var starting = false
    @State private var conflictMessage: String?
    @State private var permissionMessage: String?
    @State private var forbiddenAlert = false
    // Audience — taste pass (2026-07-31): "A cell / class" now lists the
    // broadcaster's OWN cells, not just a generic "My cell" label. See
    // `cellOptions` below for where this comes from.
    @State private var myLedCells: [LedCell] = []
    @State private var selectedCellId: String?

    /// One cell the signed-in member may go live to under scope=cell.
    private struct LedCell: Identifiable, Hashable {
        let id: String
        let name: String
    }

    init(forcedCell: (id: String, name: String)? = nil, onStarted: @escaping (GoLiveSession) -> Void) {
        self.forcedCell = forcedCell
        self.onStarted = onStarted
        _scope = State(initialValue: forcedCell != nil ? .cell : .church)
    }

    // MARK: Eligibility (advisory — see LiveBroadcastEligibility)

    private var churchEligible: Bool {
        forcedCell == nil && LiveBroadcastEligibility.churchEligible(auth.profile)
    }

    /// The cells this member may broadcast to under scope=cell. The server's
    /// own authorization for scope=cell (service.ts `createStream`) is
    /// Admin/SuperAdmin OR the cell appearing in the caller's
    /// `leader_assignments` — NOT `profile.cell_group_id` (that's just their
    /// own personal cell MEMBERSHIP, a cheap proxy `LiveBroadcastEligibility.
    /// cellEligible` uses elsewhere for a plain single-cell affordance).
    /// `GET /disciples` (the existing discipler-roster fetch — reused here
    /// rather than minting a new endpoint) is scoped by that same
    /// `leader_assignments` set, so every distinct cell it surfaces is
    /// guaranteed to authorize — same "never a false positive" invariant
    /// `LiveBroadcastEligibility` documents, just a more precise signal for
    /// a leader who leads more than one cell. Falls back to the personal-
    /// membership proxy (a single "My cell" option) when the roster fetch
    /// comes back empty — a non-leader member, or `/disciples` 403ing for a
    /// role below Instructor+ (best-effort `try?` in `loadMyLedCells`) —
    /// which is exactly today's existing behavior, unchanged for everyone
    /// this picker is new for.
    private var cellOptions: [LedCell] {
        if !myLedCells.isEmpty { return myLedCells }
        if let id = auth.profile?.cellGroupId, !id.isEmpty { return [LedCell(id: id, name: "My cell")] }
        return []
    }
    private var cellSectionAvailable: Bool { forcedCell != nil || !cellOptions.isEmpty }
    private var hasEligibleScope: Bool { churchEligible || cellSectionAvailable }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var titleValid: Bool { (1...200).contains(trimmedTitle.count) }
    private var canStart: Bool { titleValid && hasEligibleScope && !starting }

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.base) {
            header
            titleField
            kindToggle
            scopeSection
            if let conflictMessage {
                inlineNotice(conflictMessage, tint: Color(hex: 0xDC2626))
            }
            if let permissionMessage {
                permissionNotice(permissionMessage)
            }
            startButton
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.screen)
        .padding(.top, Nuru.S.sm)
        .background(Color.white)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { correctScopeIfNeeded() }
        .task { await loadMyLedCells() }
        .alert("You may not go live here", isPresented: $forbiddenAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("This scope isn't available to your account. Try a different one, or reach out to your leader.")
        }
    }

    /// If the guessed default (church, or cell when forced) turns out
    /// ineligible once the real profile is in hand, fall back to whichever
    /// scope actually IS eligible rather than leaving Start permanently
    /// disabled on an option nobody can use.
    private func correctScopeIfNeeded() {
        if scope == .church, !churchEligible, cellSectionAvailable { scope = .cell }
        else if scope == .cell, !cellSectionAvailable, churchEligible { scope = .church }
        if selectedCellId == nil { selectedCellId = cellOptions.first?.id }
    }

    /// Best-effort — a plain member's `/disciples` call 403s (Instructor+
    /// only) and that's fine: `cellOptions` already falls back to the
    /// personal-cell proxy when `myLedCells` stays empty. `forcedCell != nil`
    /// (CellInfoView's entry point) skips this entirely — that flow never
    /// shows a cell picker at all.
    private func loadMyLedCells() async {
        guard forcedCell == nil else { return }
        guard let roster = try? await MemberAPI.disciples() else { return }
        var seenIds = Set<String>()
        var cells: [LedCell] = []
        for row in roster.data {
            guard let id = row.cellGroupId, !id.isEmpty, !seenIds.contains(id) else { continue }
            seenIds.insert(id)
            let name = row.cellName?.isEmpty == false ? row.cellName! : "Cell"
            cells.append(LedCell(id: id, name: name))
        }
        guard !cells.isEmpty else { return }
        myLedCells = cells
        if selectedCellId == nil { selectedCellId = cellOptions.first?.id }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("GO LIVE").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(Nuru.gold)
                Text("Start a broadcast").font(.fraunces(19, .medium)).foregroundStyle(Nuru.navy)
            }
            Spacer(minLength: 0)
            Button { Haptics.tap(); dismiss() } label: {
                Circle().fill(Nuru.surface).frame(width: 32, height: 32)
                    .overlay(Icon(.x, size: 15, color: Nuru.navy))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TITLE").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(Nuru.muted)
            TextField("What's happening?", text: $title)
                .font(.inter(14, .regular)).foregroundStyle(Nuru.navy)
                .padding(Nuru.S.md)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                // Fail fast client-side too, mirroring the backend's z.string().max(200).
                .onChange(of: title) { _, v in if v.count > 200 { title = String(v.prefix(200)) } }
        }
    }

    private var kindToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FORMAT").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(Nuru.muted)
            HStack(spacing: 4) {
                segmentButton("Video", selected: kind == .video) { kind = .video }
                segmentButton("Audio only", selected: kind == .audio) { kind = .audio }
            }
            .padding(4)
            .background(Nuru.surface, in: Capsule())
            .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        }
    }

    @ViewBuilder private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AUDIENCE").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(Nuru.muted)
            if let forcedCell {
                scopeLabelRow(icon: .users, text: forcedCell.name)
            } else if churchEligible && cellSectionAvailable {
                HStack(spacing: 4) {
                    segmentButton("Everyone", selected: scope == .church) { scope = .church }
                    segmentButton("A cell / class", selected: scope == .cell) { scope = .cell }
                }
                .padding(4)
                .background(Nuru.surface, in: Capsule())
                .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                if scope == .church {
                    Text("Everyone — all connected members").font(.inter(11)).foregroundStyle(Nuru.muted)
                        .padding(.horizontal, 4)
                } else {
                    cellPicker
                }
            } else if churchEligible {
                scopeLabelRow(icon: .megaphone, text: "Everyone — all connected members")
            } else if cellSectionAvailable {
                cellPicker
            } else {
                Text("You don't have a church or cell to go live in yet.")
                    .font(.inter(12)).foregroundStyle(Nuru.muted)
            }
        }
    }

    /// The specific-cell list shown once "A cell / class" is the active
    /// audience: a single labelled row when there's only one option (matches
    /// the old "My cell" look exactly), or a tappable list of radio rows
    /// when a leader has more than one cell to choose from.
    @ViewBuilder private var cellPicker: some View {
        if cellOptions.count > 1 {
            VStack(spacing: 6) {
                ForEach(cellOptions) { cell in
                    Button {
                        Haptics.selection()
                        selectedCellId = cell.id
                    } label: {
                        let isSelected = selectedCellId == cell.id
                        HStack(spacing: 8) {
                            Icon(.users, size: 13, color: Nuru.goldChipText)
                            Text(cell.name).font(.inter(13, isSelected ? .bold : .semibold)).foregroundStyle(Nuru.navy)
                            Spacer(minLength: 0)
                            if isSelected { Icon(.checkCircle2, size: 15, color: Nuru.gold) }
                        }
                        .padding(.horizontal, Nuru.S.md).padding(.vertical, 10)
                        .background(isSelected ? Nuru.goldChipBg : Nuru.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Nuru.gold.opacity(0.5) : Nuru.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if let only = cellOptions.first {
            scopeLabelRow(icon: .users, text: only.name)
        }
    }

    private func segmentButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            Text(label)
                .font(.inter(12, selected ? .bold : .semibold))
                .foregroundStyle(selected ? Nuru.navy : Nuru.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background { if selected { Capsule().fill(Nuru.gold) } }
        }
        .buttonStyle(.plain)
    }

    private func scopeLabelRow(icon: Lucide, text: String) -> some View {
        HStack(spacing: 8) {
            Icon(icon, size: 14, color: Nuru.goldChipText)
            Text(text).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.md)
        .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func inlineNotice(_ text: String, tint: Color) -> some View {
        Text(text).font(.inter(12, .semibold)).foregroundStyle(tint)
            .padding(Nuru.S.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// A camera/mic denial — never a dead end (matches CheckInScannerView's
    /// deniedView pointer, inline instead of full-screen since the sheet
    /// itself stays open for another attempt).
    private func permissionNotice(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
            Button {
                Haptics.tap()
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Text("Open Settings").font(.inter(12, .bold)).foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Nuru.gold, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(Nuru.S.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var startButton: some View {
        Button {
            Task { await start() }
        } label: {
            HStack(spacing: 8) {
                if starting { ProgressView().tint(Nuru.navy) }
                else { Icon(.play, size: 15, color: Nuru.navy) }
                Text(starting ? "Starting…" : "Go live").font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(!canStart)
        .opacity(canStart ? 1 : 0.5)
    }

    // MARK: Start flow

    private func start() async {
        guard canStart else { return }
        conflictMessage = nil
        permissionMessage = nil
        starting = true
        defer { starting = false }

        // Permission gate FIRST — a hard denial must never mint a stream slot.
        let (camera, mic) = await LiveBroadcastPermissions.requestForKind(kind)
        if kind == .video, camera != .granted {
            permissionMessage = "Nuru needs camera access to go live on video. Turn it on in Settings and come back."
            Haptics.error()
            return
        }
        if mic != .granted {
            permissionMessage = "Nuru needs microphone access to go live. Turn it on in Settings and come back."
            Haptics.error()
            return
        }

        let finalScope: LiveBroadcastScopeChoice = forcedCell != nil ? .cell : scope
        let cellId: String? = finalScope == .cell
            ? (forcedCell?.id ?? selectedCellId ?? cellOptions.first?.id ?? auth.profile?.cellGroupId)
            : nil

        do {
            let created = try await MemberAPI.startLiveStream(
                scope: finalScope.rawValue, cellId: cellId, title: trimmedTitle, kind: kind.rawValue)
            Haptics.success()
            onStarted(GoLiveSession(stream: created, kind: kind, title: trimmedTitle))
            dismiss()
        } catch {
            Haptics.error()
            let api = error as? APIError
            if case .http(_, let code, let message, _)? = api {
                switch code ?? "" {
                case "CONFLICT":
                    conflictMessage = "Someone is already live there. Try a different scope, or wait until they finish."
                case "FORBIDDEN_SCOPE":
                    forbiddenAlert = true
                default:
                    conflictMessage = message
                }
            } else if api?.isNetwork == true {
                conflictMessage = "You're offline — going live needs a connection."
            } else {
                conflictMessage = api?.errorDescription ?? "Couldn't start the broadcast. Try again."
            }
        }
    }
}
