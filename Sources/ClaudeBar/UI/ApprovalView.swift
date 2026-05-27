import SwiftUI
import AppKit

@MainActor
final class ApprovalWindowController: NSObject {
    static let shared = ApprovalWindowController()

    private let panel = StatusBarPanel(width: 460, height: 480,
        viewFactory: { NSHostingView(rootView: ApprovalView()) })

    func show() { panel.show() }
    func dismiss() { panel.dismiss() }
}

struct ApprovalView: View {
    @ObservedObject private var state = AppState.shared
    @State private var denyReason = ""
    @State private var denyMode = false
    @FocusState private var reasonFocused: Bool
    @State private var showCopyToast = false
    @State private var copyToastTask: Task<Void, Never>?
    @State private var showDangerConfirm = false
    @State private var arrowKeyMonitor: Any?

    var body: some View {
        Group {
            if let approval = state.pendingApproval {
                VStack(spacing: 0) {
                    topBar(approval: approval)
                    Divider()
                    if denyMode {
                        denyConfirmContent.transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
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
                                if state.isDangerous(approval.request) {
                                    dangerWarningBanner
                                    Divider().padding(.horizontal, 18)
                                }
                                commandSection(approval)
                                if approval.request.toolName?.lowercased() == "write" {
                                    writeDiffSection(approval)
                                }
                            }
                        }
                        Divider()
                        actionBar
                            .confirmationDialog(
                                "Are you sure?",
                                isPresented: $showDangerConfirm,
                                titleVisibility: .visible
                            ) {
                                Button("Run", role: .destructive) { state.allow() }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("This command may include irreversible operations such as file deletion, moving, or permission changes.")
                            }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .onChange(of: approval.request.requestId) { _, _ in
                    withAnimation { denyMode = false }
                    denyReason = ""
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
        .onAppear {
            guard arrowKeyMonitor == nil else { return }
            arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard !self.denyMode, self.state.pendingApproval?.isBlocking == true else { return event }
                if event.keyCode == 123 { // ← Deny
                    withAnimation(.easeInOut(duration: 0.2)) { self.denyMode = true }
                    return nil
                } else if event.keyCode == 124 { // → Allow
                    self.triggerAllow()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let m = arrowKeyMonitor { NSEvent.removeMonitor(m); arrowKeyMonitor = nil }
        }
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
            title: "Possible sensitive data",
            message: ".env files may contain API keys or passwords. Are you sure you want to allow?"
        )
    }

    private var dangerWarningBanner: some View {
        warningBanner(
            icon: "exclamationmark.octagon.fill",
            color: .red,
            title: "Destructive file operation",
            message: "This may include irreversible operations such as file deletion, moving, or permission changes."
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
        if let req = state.pendingApproval?.request, state.isDangerous(req) {
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
                .help("Copy")
            }

            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    commandContent(preview: preview, toolName: toolName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
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
                        Text("Copied")
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
        NSPasteboard.copy(text)
        copyToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) { showCopyToast = true }
        copyToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showCopyToast = false }
        }
    }

    // MARK: - Deny confirm view

    private var denyConfirmContent: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Why are you denying?", systemImage: "text.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $denyReason)
                        .font(.callout)
                        .frame(minHeight: 100, maxHeight: 160)
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08), lineWidth: 1))
                        .scrollContentBackground(.hidden)
                        .focused($reasonFocused)
                    if denyReason.isEmpty {
                        Text("Optional reason or instructions…")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.top, 18)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Spacer(minLength: 0)

            Divider()

            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { denyMode = false }
                    denyReason = ""
                } label: {
                    Text("Back").font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                }
                .controlSize(.large).buttonStyle(.bordered)
                .keyboardShortcut(.escape)

                Button(role: .destructive) {
                    state.deny(reason: denyReason)
                    denyReason = ""
                    denyMode = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark").font(.callout.weight(.semibold))
                        Text("Confirm Deny").font(.callout.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 3)
                }
                .controlSize(.large).buttonStyle(.borderedProminent).tint(.red)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .onAppear { reasonFocused = true }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        let isBlocking = state.pendingApproval?.isBlocking ?? true
        return VStack(spacing: 0) {
            if !isBlocking {
                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.2)) { denyMode = true }
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
                        withAnimation(.easeInOut(duration: 0.2)) { denyMode = true }
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

    // MARK: - Write diff section

    @ViewBuilder
    private func writeDiffSection(_ approval: PendingApproval) -> some View {
        if let rawInput = approval.request.toolInputRaw,
           case .string(let filePath) = rawInput["file_path"],
           case .string(let newContent) = rawInput["content"] {
            let oldContent = (try? String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)) ?? ""
            let oldLines = oldContent.isEmpty ? [] : oldContent.components(separatedBy: "\n")
            let newLines = newContent.components(separatedBy: "\n")
            let diffLines = buildDiff(old: oldLines, new: newLines)
            let addCount = diffLines.filter { $0.kind == .added }.count
            let delCount = diffLines.filter { $0.kind == .removed }.count

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Diff", systemImage: "arrow.left.arrow.right.square.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if oldLines.isEmpty {
                        Text("New file")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 6) {
                            Text("+\(addCount)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                            Text("-\(delCount)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                }
                if !diffLines.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(diffLines.prefix(80).enumerated()), id: \.offset) { _, line in
                                Text(line.linePrefix + line.text)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(line.displayColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                    .padding(10)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08), lineWidth: 1))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Diff helpers

private struct DiffLine {
    enum Kind { case context, added, removed }
    var kind: Kind
    var text: String
    var linePrefix: String { kind == .added ? "+ " : kind == .removed ? "- " : "  " }
    var displayColor: Color { kind == .added ? .green : kind == .removed ? .red : .secondary }
}

private func buildDiff(old: [String], new: [String]) -> [DiffLine] {
    var result: [DiffLine] = []
    var oi = 0
    var ni = 0
    while oi < old.count || ni < new.count {
        if oi < old.count && ni < new.count && old[oi] == new[ni] {
            result.append(DiffLine(kind: .context, text: old[oi]))
            oi += 1
            ni += 1
        } else {
            if oi < old.count { result.append(DiffLine(kind: .removed, text: old[oi])); oi += 1 }
            if ni < new.count { result.append(DiffLine(kind: .added,   text: new[ni])); ni += 1 }
        }
    }
    return collapseContext(result, window: 3)
}

private func collapseContext(_ lines: [DiffLine], window: Int) -> [DiffLine] {
    let changedIndices = lines.indices.filter { lines[$0].kind != .context }
    guard !changedIndices.isEmpty else { return [] }
    var keep = IndexSet()
    for idx in changedIndices {
        keep.insert(integersIn: max(0, idx - window)...min(lines.count - 1, idx + window))
    }
    return keep.map { lines[$0] }
}

// MARK: - AskQuestion popup

@MainActor
final class AskQuestionWindowController: NSObject {
    static let shared = AskQuestionWindowController()
    private let panel = StatusBarPanel(width: 460, height: 120,
        viewFactory: { NSHostingView(rootView: AskQuestionView()) })

    func show() { panel.show() }
    func dismiss() { panel.dismiss() }
}

struct AskQuestionView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Group {
            if let request = state.pendingAskQuestion {
                VStack(spacing: 0) {
                    topBar(request: request)
                    Divider()
                    bodySection(request: request)
                }
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
            Text("Claude is asking a question — answer in your terminal")
                .font(.callout)
                .foregroundStyle(.primary)

            Text("Due to Claude Code limitations, you cannot reply from here")
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
