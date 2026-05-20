import SwiftUI
import AppKit

@MainActor
final class ApprovalWindowController: NSObject {
    static let shared = ApprovalWindowController()
    private var panel: NSPanel?

    private static let width: CGFloat  = 460
    private static let height: CGFloat = 480

    func show() {
        if panel == nil { createPanel() }
        guard let p = panel else { return }
        positionPanel(p)
        guard !p.isVisible else { return }
        p.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func positionPanel(_ p: NSPanel) {
        guard let button = StatusBarButtonStore.shared.button,
              let buttonWindow = button.window else { return }
        let buttonScreenFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonScreenFrame.midX - Self.width / 2
        let y = buttonScreenFrame.minY - Self.height - 6
        if let screen = buttonWindow.screen ?? NSScreen.main {
            x = max(screen.visibleFrame.minX, min(x, screen.visibleFrame.maxX - Self.width))
        }
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func createPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingView = NSHostingView(rootView: ApprovalView())
        hostingView.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        hostingView.autoresizingMask = [.width, .height]
        p.contentView = hostingView
        self.panel = p
    }
}

struct ApprovalView: View {
    @ObservedObject private var state = AppState.shared
    @State private var denyReason = ""
    @FocusState private var reasonFocused: Bool
    @State private var showCopyToast = false
    @State private var copyToastTask: Task<Void, Never>?
    @State private var showDangerConfirm = false

    var body: some View {
        Group {
            if let approval = state.pendingApproval {
                VStack(spacing: 0) {
                    topBar(approval: approval)
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
                            if approval.isEnvWarning {
                                envWarningBanner
                                Divider().padding(.horizontal, 18)
                            }
                            if approval.request.isDangerousCommand {
                                dangerWarningBanner
                                Divider().padding(.horizontal, 18)
                            }
                            commandSection(approval)
                            Divider().padding(.horizontal, 18)
                            denySection
                        }
                    }
                    Divider()
                    actionBar
                        .confirmationDialog(
                            "本当に実行しますか？",
                            isPresented: $showDangerConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("実行する", role: .destructive) {
                                state.allow(); denyReason = ""
                            }
                            Button("キャンセル", role: .cancel) {}
                        } message: {
                            Text("このコマンドはファイルの削除・移動・権限変更など、取り消しのきかない操作を含む可能性があります。")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Top bar

    private func topBar(approval: PendingApproval) -> some View {
        let color = toolColor(for: approval.request.toolName)
        return HStack(spacing: 8) {
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
                    Text(approval.request.projectLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

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

    // MARK: - Warning banners

    private var envWarningBanner: some View {
        warningBanner(
            icon: "exclamationmark.triangle.fill",
            color: .orange,
            title: "機密情報が含まれている可能性があります",
            message: ".env ファイルには API キーやパスワードが含まれることがあります。本当に許可しますか？"
        )
    }

    private var dangerWarningBanner: some View {
        warningBanner(
            icon: "exclamationmark.octagon.fill",
            color: .red,
            title: "ファイルを変更・削除する操作があります",
            message: "ファイルの削除・移動・権限変更など、取り消しのきかない操作を含む可能性があります。"
        )
    }

    private func warningBanner(icon: String, color: Color, title: String, message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
    }

    private func triggerAllow() {
        if state.pendingApproval?.request.isDangerousCommand == true {
            showDangerConfirm = true
        } else {
            state.allow(); denyReason = ""
        }
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
        let preview = approval.request.commandPreview
        let toolName = approval.request.toolName?.lowercased()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Command", systemImage: "chevron.right.square.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { copyCommand(preview) } label: {
                    Image(systemName: showCopyToast ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(showCopyToast ? .green : .secondary)
                        .animation(.easeInOut(duration: 0.15), value: showCopyToast)
                }
                .buttonStyle(.plain)
                .help("コピー")
            }

            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    commandContent(preview: preview, toolName: toolName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 130)
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { copyCommand(preview) }

                if showCopyToast {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("コピーしました")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func commandContent(preview: String, toolName: String?) -> some View {
        if preview.isEmpty {
            Text("(no preview available)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        } else if shouldRenderMarkdown(preview: preview, toolName: toolName),
                  let attributed = try? AttributedString(
                    markdown: preview,
                    options: .init(interpretedSyntax: .full)
                  ) {
            Text(attributed)
                .font(.callout)
                .foregroundStyle(.primary)
        } else {
            Text(preview)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private func shouldRenderMarkdown(preview: String, toolName: String?) -> Bool {
        guard let tool = toolName, ["write", "edit", "multiedit"].contains(tool) else { return false }
        return preview.contains("\n#") || preview.hasPrefix("#") || preview.contains("**") || preview.contains("```")
    }

    private func copyCommand(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) { showCopyToast = true }
        copyToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showCopyToast = false }
        }
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
                        triggerAllow()
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
                        triggerAllow()
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
        case "askuserquestion":              return "questionmark.circle.fill"
        default:                             return "bolt.fill"
        }
    }

    private func toolColor(for name: String?) -> Color {
        switch name?.lowercased() {
        case "bash":                         return .orange
        case "write", "edit", "multiedit":   return .blue
        case "askfollowupquestion":          return .teal
        case "askuserquestion":              return .indigo
        default:                             return .purple
        }
    }
}

// MARK: - AskQuestion popup

@MainActor
final class AskQuestionWindowController: NSObject {
    static let shared = AskQuestionWindowController()
    private var popover: NSPopover?

    private static let width: CGFloat  = 460
    private static let height: CGFloat = 120

    func show() {
        if popover == nil { createPopover() }
        guard let button = StatusBarButtonStore.shared.button else { return }
        guard !(popover?.isShown ?? false) else { return }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async { [weak self] in
            self?.popover?.contentViewController?.view.window?.resignKey()
        }
    }

    func dismiss() {
        popover?.performClose(nil)
    }

    private func createPopover() {
        let p = NSPopover()
        p.contentSize = NSSize(width: Self.width, height: Self.height)
        p.behavior = .applicationDefined
        p.animates = true
        p.contentViewController = NSHostingController(rootView: AskQuestionView())
        self.popover = p
    }
}

struct AskQuestionView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        if let request = state.pendingAskQuestion {
            VStack(spacing: 0) {
                topBar(request: request)
                Divider()
                bodySection(request: request)
            }
        }
    }

    private func topBar(request: HookRequest) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.indigo.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.indigo)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AskUserQuestion")
                    .font(.subheadline.weight(.semibold))
                Text(request.projectLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button { focusTerminal(request: request) } label: {
                Image(systemName: "terminal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Switch to terminal")

            Button { state.dismissAskQuestion() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.indigo.opacity(0.10))
    }

    private func bodySection(request: HookRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude が質問しています — ターミナルで回答してください")
                .font(.callout)
                .foregroundStyle(.primary)

            Text("Claude Code の仕様上、ここから回答を送ることはできません")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func focusTerminal(request: HookRequest) {
        let dir = request.workingDirectory
        Task.detached {
            if let d = dir { await focusSession(dir: d) } else { await focusAnyTerminal() }
        }
    }
}
