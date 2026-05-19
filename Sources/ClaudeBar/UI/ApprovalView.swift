import SwiftUI
import AppKit

@MainActor
final class ApprovalWindowController: NSObject {
    static let shared = ApprovalWindowController()
    private var popover: NSPopover?

    func show() {
        if popover == nil { createPopover() }
        guard let button = StatusBarButtonStore.shared.button else { return }
        if let hc = popover?.contentViewController as? NSHostingController<ApprovalView> {
            hc.rootView = ApprovalView()
        }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func dismiss() {
        popover?.performClose(nil)
    }

    private func createPopover() {
        let p = NSPopover()
        p.contentSize = NSSize(width: 460, height: 480)
        p.behavior = .transient
        p.animates = true
        p.contentViewController = NSHostingController(rootView: ApprovalView())
        self.popover = p
    }
}

struct ApprovalView: View {
    @ObservedObject private var state = AppState.shared
    @State private var denyReason = ""
    @FocusState private var reasonFocused: Bool

    var body: some View {
        if let approval = state.pendingApproval {
            VStack(spacing: 0) {
                topBar(approval: approval)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let ctx = approval.request.context, !ctx.isEmpty {
                            intentSection(ctx)
                            Divider().padding(.horizontal, 18)
                        }
                        commandSection(approval)
                        Divider().padding(.horizontal, 18)
                        denySection
                    }
                }
                Divider()
                actionBar
            }
        } else {
            VStack(spacing: 10) {
                ProgressView()
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
        return HStack(spacing: 12) {
            // Tool icon badge
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

            Button { focusTerminal() } label: {
                Image(systemName: "terminal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Switch to terminal")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(color.opacity(0.12))
    }

    // MARK: - Intent section

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
                // Non-blocking: send terminal keystrokes matching Claude Code's 1/2/3 prompt
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
                // Blocking: respond to hook
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
