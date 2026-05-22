import SwiftUI

struct MenuBarView: View {
    @ObservedObject private var state = AppState.shared
    let onShowApproval: () -> Void
    let onOpenSetup: () -> Void
    let onOpenStats: () -> Void

    @State private var instructionTarget: SessionInfo?
    @State private var sessionsExpanded = false
    @State private var selectedSessionId: String?
    @State private var displayedTotal: Int = 0
    @State private var countTask: Task<Void, Never>?
    @State private var pulse = false

    private static let sessionLimit = 5

    var body: some View {
        Group {
            if let target = instructionTarget {
                InstructionForm(session: target, onDone: { instructionTarget = nil })
            } else {
                dashboard
            }
        }
        .frame(width: 320)
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        VStack(spacing: 0) {
            statusSection
            if !state.displayedSessions.isEmpty {
                Divider()
                sessionsSection
            } else if !state.isSetupComplete {
                Divider()
                Button("Setup Claude Code", action: onOpenSetup)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(16)
            }
        }
        .onChange(of: state.popoverOpenCount) { _, _ in startCountUp(to: state.todaySummary.total) }
        .onChange(of: state.todaySummary.total) { _, newVal in
            if countTask == nil {
                withAnimation(.easeOut(duration: 0.25)) { displayedTotal = newVal }
            }
        }
        .onDisappear {
            selectedSessionId = nil
            countTask?.cancel()
        }
        .task(id: selectedSessionId) {
            guard selectedSessionId != nil else { return }
            do {
                try await Task.sleep(for: .seconds(5))
                withAnimation(.easeInOut(duration: 0.2)) { selectedSessionId = nil }
            } catch {}
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack(alignment: .center, spacing: 12) {
            statusOrb
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if state.todaySummary.total > 0 {
                Button(action: onOpenStats) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("TODAY")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(statusColor)
                            .tracking(2.5)
                        Text("\(displayedTotal)")
                            .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("View today's details")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func startCountUp(to target: Int) {
        countTask?.cancel()
        displayedTotal = 0
        guard target > 0 else { return }
        let steps = 50
        let intervalNs = UInt64(1_000_000_000) / UInt64(steps)
        countTask = Task { @MainActor in
            for i in 1...steps {
                do { try await Task.sleep(nanoseconds: intervalNs) } catch { return }
                let t = Double(i) / Double(steps)
                let eased = t < 0.5 ? 4 * t * t * t : 1.0 - pow(-2 * t + 2, 3) / 2
                displayedTotal = Int(Double(target) * eased)
            }
            displayedTotal = target
            countTask = nil
        }
    }

    private var statusOrb: some View {
        ZStack {
            if state.isServerRunning {
                Circle()
                    .fill(statusColor)
                    .opacity(pulse ? 0 : 0.45)
                    .scaleEffect(pulse ? 2.8 : 1.0)
                    .frame(width: 11, height: 11)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulse)
                    .onAppear { pulse = true }
                    .onDisappear { pulse = false }
            }
            Circle().fill(statusColor.opacity(0.12)).frame(width: 34, height: 34)
            Circle().fill(statusColor.opacity(0.25)).frame(width: 22, height: 22)
            Circle().fill(statusColor).frame(width: 11, height: 11)
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        let all = state.displayedSessions
        let limit = Self.sessionLimit
        let visible = sessionsExpanded ? all : Array(all.prefix(limit))
        let overflow = all.count - limit

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Active Sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(all.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(visible) { session in
                sessionRow(session)
            }

            if overflow > 0 && !sessionsExpanded {
                Button { sessionsExpanded = true } label: {
                    Text("+\(overflow) more")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if sessionsExpanded && all.count > limit {
                Button { sessionsExpanded = false } label: {
                    Text("Show less")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 6)
    }

    private func pendingCount(for session: SessionInfo) -> Int {
        state.approvalQueue.filter {
            session.matches(sessionId: $0.request.sessionId, workingDirectory: $0.request.workingDirectory)
        }.count
    }

    private func isDone(_ session: SessionInfo) -> Bool {
        state.pendingCompletions.contains {
            $0.matches(sessionId: session.id, workingDirectory: session.workingDirectory)
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionInfo) -> some View {
        let pending = pendingCount(for: session)
        let done = isDone(session)
        let isSelected = selectedSessionId == session.id

        HStack(spacing: 0) {

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor)
                .frame(width: 3)
                .scaleEffect(y: isSelected && pending == 0 ? 1 : 0, anchor: .center)
                .animation(
                    isSelected ? .spring(duration: 0.32, bounce: 0.35) : .easeOut(duration: 0.15),
                    value: isSelected
                )
                .padding(.vertical, 8)
                .padding(.leading, 6)

            HStack(spacing: 10) {
                Image(systemName: pending > 0 ? "bell.fill" : "terminal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(pending > 0 ? .orange : .secondary)
                    .frame(width: 28, height: 28)
                    .background((pending > 0 ? Color.orange : Color.green).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7))

                Text(session.workingDirectory?.projectName ?? String(session.id.prefix(12)) + "…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if isSelected && pending == 0 {
                    HStack(spacing: 4) {
                        inlineAction("terminal", help: "Focus terminal") {
                            let dir = session.workingDirectory
                            Task.detached {
                                if let d = dir { await focusSession(dir: d) } else { await focusAnyTerminal() }
                            }
                        }
                        inlineAction("paperplane.fill", help: "Send message") {
                            state.clearCompletion(for: session)
                            instructionTarget = session
                        }
                        inlineAction("xmark", help: "Dismiss session") {
                            selectedSessionId = nil
                            state.dismissSession(session)
                        }
                    }
                    .padding(.trailing, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if pending > 0 {
                    Text("\(pending)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.orange, in: Capsule())
                        .padding(.trailing, 14)
                } else if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.trailing, 14)
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 7)
        }
        .frame(height: 44)
        .background(
            pending > 0 ? Color.orange.opacity(0.07) :
            isSelected  ? Color.accentColor.opacity(0.08) :
            done        ? Color.green.opacity(0.06) : Color.clear,
            in: Rectangle()
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if pending > 0 { onShowApproval() }
            else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedSessionId = session.id
                }
            }
        }
    }

    private func inlineAction(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(help)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if state.serverError != nil     { return Color(nsColor: .systemRed)    }
        if state.pendingApproval != nil { return Color(nsColor: .systemOrange) }
        if state.isServerRunning        { return Color(nsColor: .systemGreen)  }
        return Color(nsColor: .systemGray)
    }

    private var statusTitle: String {
        if state.pendingApproval != nil { return "Waiting for approval" }
        if state.isServerRunning        { return "Connected"            }
        return "Not running"
    }

    private var statusSubtitle: String {
        if let err = state.serverError  { return err }
        if state.pendingApproval != nil { return "Claude wants to use \(state.pendingApproval?.request.toolName ?? "a tool")" }
        if state.isServerRunning        { return "Unix socket active" }
        return state.isSetupComplete ? "Server not started" : "Run setup to connect"
    }
}

// MARK: - Instruction Form

private struct InstructionForm: View {
    let session: SessionInfo
    let onDone: () -> Void

    private enum SendStatus { case copied, notFound }

    @State private var text = ""
    @State private var isSending = false
    @State private var sendStatus: SendStatus? = nil
    @FocusState private var focused: Bool

    private var projectName: String { session.workingDirectory?.projectName ?? session.id }
    private var shortPath: String   { session.workingDirectory.shortenedPath }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Button { onDone() } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Image(systemName: "terminal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                    .frame(width: 26, height: 26)
                    .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(projectName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(shortPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer()

                Button {
                    let dir = session.workingDirectory
                    Task.detached {
                        if let d = dir { await focusSession(dir: d) } else { await focusAnyTerminal() }
                    }
                } label: {
                    Image(systemName: "terminal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Switch to terminal")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            // Input area
            VStack(alignment: .leading, spacing: 8) {
                Label("New instruction", systemImage: "text.cursor")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .font(.callout)
                    .frame(minHeight: 90, maxHeight: 160)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                    )
                    .focused($focused)
                    .scrollContentBackground(.hidden)

                if sendStatus == .copied {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Copied to clipboard — paste with ⌘V in your terminal", systemImage: "doc.on.clipboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Allow Accessibility Access…") { openAccessibilitySettings() }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } else if sendStatus == .notFound {
                    Label("Terminal not found", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            // Actions
            HStack(spacing: 8) {
                Button("Cancel") { onDone() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)

                Spacer()

                Button {
                    send()
                } label: {
                    HStack(spacing: 5) {
                        if isSending {
                            BrailleSpinner()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Send")
                    }
                    .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .controlSize(.large)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .onAppear { focused = true }
    }

    private func send() {
        let instruction = text
        let dir = session.workingDirectory
        isSending = true
        sendStatus = nil
        Task.detached {
            let result = await sendToSession(dir: dir, text: instruction)
            await MainActor.run {
                isSending = false
                switch result {
                case .sent:       onDone()
                case .copiedOnly: sendStatus = .copied
                case .failed:     sendStatus = .notFound
                }
            }
        }
    }
}
