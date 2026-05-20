import SwiftUI
import AppKit

@MainActor
final class ApprovalWindowController: NSObject {
    static let shared = ApprovalWindowController()
    private var popover: NSPopover?

    private static let width: CGFloat     = 460
    private static let compactH: CGFloat  = 68
    private static let expandedH: CGFloat = 480

    func show(expanded: Bool = false, keepingFocus: Bool = false) {
        if popover == nil { createPopover() }
        guard let button = StatusBarButtonStore.shared.button else { return }
        AppState.shared.approvalExpanded = expanded
        popover?.contentSize = NSSize(width: Self.width, height: expanded ? Self.expandedH : Self.compactH)
        if keepingFocus { NSApp.activate(ignoringOtherApps: true) }
        guard !(popover?.isShown ?? false) else { return }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if !keepingFocus {
            // Yield key window so the user's keyboard focus is not interrupted
            DispatchQueue.main.async { [weak self] in
                self?.popover?.contentViewController?.view.window?.resignKey()
            }
        }
    }

    func dismiss() {
        popover?.performClose(nil)
    }

    func setExpanded(_ expanded: Bool) {
        popover?.contentSize = NSSize(width: Self.width, height: expanded ? Self.expandedH : Self.compactH)
    }

    private func createPopover() {
        let p = NSPopover()
        p.contentSize = NSSize(width: Self.width, height: Self.compactH)
        p.behavior = .applicationDefined
        p.animates = true
        p.contentViewController = NSHostingController(rootView: ApprovalView())
        self.popover = p
    }
}

struct ApprovalView: View {
    @ObservedObject private var state = AppState.shared
    @State private var denyReason = ""
    @FocusState private var reasonFocused: Bool

    private var isExpanded: Bool { state.approvalExpanded }

    var body: some View {
        if let approval = state.pendingApproval {
            VStack(spacing: 0) {
                topBar(approval: approval)
                if isExpanded {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if let ctx = approval.request.context?.nilIfEmpty {
                                intentSection(ctx)
                                Divider().padding(.horizontal, 18)
                            } else {
                                switch state.intentState {
                                case .found(let text):
                                    intentSection(text)
                                    Divider().padding(.horizontal, 18)
                                case .loading:
                                    intentLoadingSection
                                    Divider().padding(.horizontal, 18)
                                case .none:
                                    intentSection(syntheticIntent(for: approval.request))
                                    Divider().padding(.horizontal, 18)
                                }
                            }
                            commandSection(approval)
                            Divider().padding(.horizontal, 18)
                            denySection
                        }
                    }
                    Divider()
                    actionBar
                }
            }
        } else {
            VStack(spacing: 10) {
                BrailleSpinner()
                Text("Waiting for hook event…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Top bar

    private func topBar(approval: PendingApproval) -> some View {
        let color = toolColor(for: approval.request.toolName)
        return HStack(spacing: 8) {
            // Tappable expand area
            Button { toggleExpanded() } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(color.opacity(0.14))
                            .frame(width: 36, height: 36)
                        Image(systemName: toolIcon(for: approval.request.toolName))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(approval.request.toolName ?? "Unknown tool")
                            .font(.subheadline.weight(.semibold))
                        Text(projectLabel(for: approval.request))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            Button { focusTerminal() } label: {
                Image(systemName: "terminal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Switch to terminal")

            Button { ApprovalWindowController.shared.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(color.opacity(0.12))
    }

    private func toggleExpanded() {
        let next = !state.approvalExpanded
        state.approvalExpanded = next
        ApprovalWindowController.shared.setExpanded(next)
    }

    // MARK: - Intent section

    private var intentLoadingSection: some View {
        HStack(spacing: 6) {
            BrailleSpinner()
            Text("Analyzing intent…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func intentSection(_ context: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Claude's intent", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(context)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Command section

    private func commandSection(_ approval: PendingApproval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Command", systemImage: "chevron.right.square.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            let preview = approval.request.commandPreview
            ScrollView {
                Text(preview.isEmpty ? "(no preview available)" : preview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(preview.isEmpty ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 130)
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Deny field

    private var denySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Deny reason", systemImage: "text.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Optional reason or instructions…", text: $denyReason, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .focused($reasonFocused)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        let isBlocking = state.pendingApproval?.isBlocking ?? true
        return VStack(spacing: 0) {
            if !isBlocking {
                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        state.deny(reason: denyReason); denyReason = ""
                    } label: {
                        Text("3. No").font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered).tint(.red).controlSize(.large)
                    .keyboardShortcut("3", modifiers: [])
                    .keyboardShortcut(.escape)

                    Button {
                        state.allow(); denyReason = ""
                    } label: {
                        Text("1. Yes").font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered).tint(.green).controlSize(.large)
                    .keyboardShortcut("1", modifiers: [])

                    Button {
                        state.allowAll(); denyReason = ""
                    } label: {
                        Text("2. Yes, all").font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)
                    .keyboardShortcut("2", modifiers: [])
                    .keyboardShortcut(.return)
                }
            } else {
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        state.deny(reason: denyReason); denyReason = ""
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark").font(.callout.weight(.semibold))
                            Text("Deny").font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                    }
                    .controlSize(.large).buttonStyle(.bordered).tint(.red)
                    .keyboardShortcut("d", modifiers: [])
                    .keyboardShortcut(.escape)

                    Button {
                        state.allow(); denyReason = ""
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.callout.weight(.semibold))
                            Text("Allow").font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                    }
                    .controlSize(.large).buttonStyle(.borderedProminent).tint(.green)
                    .keyboardShortcut("a", modifiers: [])
                    .keyboardShortcut(.return)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private func focusTerminal() {
        let dir = state.pendingApproval?.request.workingDirectory
        Task.detached {
            if let d = dir { await focusSession(dir: d) } else { await focusAnyTerminal() }
        }
    }

    private func projectLabel(for request: HookRequest) -> String {
        if let dir = request.workingDirectory {
            return (dir as NSString).lastPathComponent
        }
        return request.sessionId.map { "Session \(String($0.prefix(12)))…" } ?? ""
    }

    private func syntheticIntent(for request: HookRequest) -> String {
        switch request.toolName?.lowercased() {
        case "bash":                       return "Running 1 shell command…"
        case "write":                      return "Writing 1 file…"
        case "edit", "multiedit":          return "Editing 1 file…"
        case "askfollowupquestion":        return "Asking a follow-up question…"
        default:
            if let name = request.toolName { return "Running \(name)…" }
            return "Running tool…"
        }
    }

    private func toolIcon(for name: String?) -> String {
        switch name?.lowercased() {
        case "bash":                         return "terminal.fill"
        case "write", "edit", "multiedit":   return "pencil.line"
        case "askfollowupquestion":          return "questionmark.bubble.fill"
        default:                             return "bolt.fill"
        }
    }

    private func toolColor(for name: String?) -> Color {
        switch name?.lowercased() {
        case "bash":                         return .orange
        case "write", "edit", "multiedit":   return .blue
        case "askfollowupquestion":          return .teal
        default:                             return .purple
        }
    }
}
