import AppKit
import SwiftUI
import Combine

// Display state shared between indicator panel and confirm panel views.
@MainActor
final class VoiceOverlayDisplayState: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var audioLevel: Float = 0
    @Published var errorMessage: String? = nil
    @Published var pendingText: String? = nil
    @Published var editingText: String = ""
}

@MainActor
final class VoiceOverlayWindowController {
    static let shared = VoiceOverlayWindowController()

    private var indicatorPanel: NSPanel?
    private var confirmPanel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var indicatorFadeTimer: Timer?
    private var confirmFadeTimer: Timer?
    private var indicatorShowing = false
    private let displayState = VoiceOverlayDisplayState()
    private weak var service: VoiceInputService?
    private var pendingConfirmApp: NSRunningApplication?
    private var keyMonitor: Any?

    private init() {}

    func setup(service: VoiceInputService) {
        self.service = service
        cancellables.removeAll()

        service.$audioLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in self?.displayState.audioLevel = level }
            .store(in: &cancellables)

        service.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] msg in
                guard let self else { return }
                displayState.errorMessage = msg
                if msg != nil {
                    showIndicator()
                } else if !displayState.isRecording && !displayState.isTranscribing && displayState.pendingText == nil {
                    hideIndicator()
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(service.$isRecording, service.$isTranscribing)
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording, isTranscribing in
                guard let self else { return }
                let wasRecording = self.displayState.isRecording
                displayState.isRecording = isRecording
                displayState.isTranscribing = isTranscribing
                // Capture frontmost app when recording starts (ClaudeBar is not active yet)
                if isRecording && !wasRecording && confirmPanel == nil {
                    pendingConfirmApp = NSWorkspace.shared.frontmostApplication
                }
                if isRecording || isTranscribing {
                    showIndicator()
                } else if displayState.errorMessage == nil && (displayState.pendingText == nil || confirmPanel != nil) {
                    hideIndicator()
                }
            }
            .store(in: &cancellables)

        service.$pendingText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                if let text {
                    ClLog.voice.debug("[pendingText sink] got text='\(text)' pendingApproval=\(AppState.shared.pendingApproval != nil)")
                    // Feature 1: 承認パネル表示中ならキーワードで即承認・拒否
                    if AppState.shared.pendingApproval != nil {
                        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let allowWords = ["はい", "許可", "yes", "ok"]
                        let denyWords  = ["いいえ", "拒否", "no"]
                        if allowWords.contains(where: { lower.contains($0) }) {
                            self.service?.pendingText = nil
                            AppState.shared.allow()
                            showBriefFeedback("承認しました")
                            return
                        } else if denyWords.contains(where: { lower.contains($0) }) {
                            self.service?.pendingText = nil
                            AppState.shared.deny(reason: "")
                            showBriefFeedback("拒否しました")
                            return
                        }
                    }
                    displayState.pendingText = text
                    displayState.editingText = text
                    startKeyMonitor()
                    hideIndicatorImmediate()
                    showConfirmPanel()
                } else {
                    displayState.pendingText = nil
                    stopKeyMonitor()
                    hideConfirmPanel()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Confirm actions

    func confirmAndInsert(edited: String) {
        ClLog.voice.debug("[confirmAndInsert] edited='\(edited)'")
        let original = displayState.pendingText ?? ""
        if AppState.shared.correctionEnabled, !edited.isEmpty, edited != original {
            VoiceCorrectionService.shared.save(original: original, corrected: edited)
        }
        let targetApp = pendingConfirmApp
        pendingConfirmApp = nil
        service?.pendingText = nil
        displayState.pendingText = nil
        stopKeyMonitor()
        hideConfirmPanel()
        guard !edited.isEmpty else { return }
        AppState.shared.appendVoiceHistory(edited)
        _ = targetApp?.activate(options: .activateIgnoringOtherApps)
        ClLog.voice.debug("[confirmAndInsert] activating targetApp=\(targetApp?.localizedName ?? "nil") then insertText in 0.2s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            insertText(edited)
        }
    }

    func pasteText(_ text: String) {
        let targetApp = NSWorkspace.shared.frontmostApplication
        _ = targetApp?.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            insertText(text)
        }
    }

    func cancelPending() {
        pendingConfirmApp = nil
        service?.pendingText = nil
        service?.cancelIfActive()
        displayState.pendingText = nil
        stopKeyMonitor()
        hideConfirmPanel()
    }

    private func showBriefFeedback(_ message: String) {
        displayState.errorMessage = message
        showIndicator()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.displayState.errorMessage == message else { return }
            self.displayState.errorMessage = nil
            self.hideIndicator()
        }
    }

    // MARK: - Key monitor (Esc / no-op; TextEditor handles typing natively)

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.displayState.pendingText != nil else { return event }
            switch event.keyCode {
            case 36 where event.modifierFlags.contains(.command): // Cmd+Return → 確定
                self.confirmAndInsert(edited: self.displayState.editingText)
                return nil
            case 53: // Escape → キャンセル
                self.cancelPending()
                return nil
            default:
                return event
            }
        }
    }

    private func stopKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // MARK: - Indicator panel (nonactivating)

    private func showIndicator() {
        if indicatorPanel == nil { createIndicatorPanel() }
        guard let panel = indicatorPanel else { return }

        let wasShowing = indicatorShowing
        indicatorShowing = true

        if !wasShowing {
            indicatorFadeTimer?.invalidate()
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()

        // Defer size calculation to let SwiftUI complete its layout pass first.
        // Always recalculate: content changes size between recording (wave bars) and transcribing (spinner).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.indicatorShowing,
                  let panel = self.indicatorPanel,
                  let screen = NSScreen.main else { return }
            panel.contentView?.layoutSubtreeIfNeeded()
            let size = panel.contentView?.fittingSize ?? .zero
            if size.width > 10 && size.height > 10 {
                let f = screen.visibleFrame
                panel.setContentSize(size)
                panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + 60))
            }
            if !wasShowing {
                self.animatePanel(panel, &self.indicatorFadeTimer, to: 1, duration: 0.5)
            }
        }
    }

    private func hideIndicatorImmediate() {
        indicatorFadeTimer?.invalidate()
        indicatorFadeTimer = nil
        indicatorShowing = false
        indicatorPanel?.alphaValue = 0
        indicatorPanel?.orderOut(nil)
    }

    private func hideIndicator() {
        indicatorShowing = false
        indicatorFadeTimer?.invalidate()
        guard let panel = indicatorPanel else { return }
        animatePanel(panel, &indicatorFadeTimer, to: 0, duration: 0.5)
    }

    private func createIndicatorPanel() {
        let hosting = NSHostingView(rootView:
            IndicatorHost(state: displayState) { [weak self] in self?.service?.cancelIfActive() }
        )
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.contentView = hosting
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        indicatorPanel = p
    }

    // MARK: - Confirm panel (can become key)

    private func showConfirmPanel() {
        confirmPanel?.orderOut(nil)
        confirmPanel = nil
        confirmFadeTimer?.invalidate()

        let hosting = NSHostingView(rootView:
            ConfirmHost(
                state: displayState,
                onConfirm: { [weak self] edited in self?.confirmAndInsert(edited: edited) },
                onCancel: { [weak self] in self?.cancelPending() }
            )
        )

        let p = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 200),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.contentView = hosting
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        confirmPanel = p

        p.alphaValue = 0
        p.orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.confirmPanel, let screen = NSScreen.main else { return }
            if let size = panel.contentView?.fittingSize {
                let f = screen.visibleFrame
                panel.setContentSize(size)
                panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2,
                                             y: f.midY - panel.frame.height / 2))
            }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            self.animatePanel(panel, &self.confirmFadeTimer, to: 1, duration: 0.4)
        }
    }

    private func hideConfirmPanel() {
        confirmFadeTimer?.invalidate()
        confirmFadeTimer = nil
        confirmPanel?.orderOut(nil)
        confirmPanel = nil
    }

    // MARK: - Fade helper

    private func animatePanel(_ panel: NSPanel, _ timerSlot: inout Timer?, to target: CGFloat, duration: Double) {
        let startAlpha = panel.alphaValue
        let interval = 1.0 / 60.0
        var elapsed = 0.0
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak panel] t in
            guard let panel else { t.invalidate(); return }
            elapsed += interval
            let progress = min(elapsed / duration, 1.0)
            let eased = progress < 0.5 ? 2 * progress * progress : 1 - 2 * (1 - progress) * (1 - progress)
            panel.alphaValue = startAlpha + CGFloat(eased) * (target - startAlpha)
            if progress >= 1.0 { t.invalidate(); if target == 0 { panel.orderOut(nil) } }
        }
        RunLoop.main.add(timer, forMode: .common)
        timerSlot = timer
    }
}

// MARK: - Panel subclass

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - SwiftUI hosts

private struct IndicatorHost: View {
    @ObservedObject var state: VoiceOverlayDisplayState
    let onCancel: () -> Void

    var body: some View {
        VoiceIndicatorView(
            isRecording: state.isRecording,
            isTranscribing: state.isTranscribing,
            audioLevel: state.audioLevel,
            errorMessage: state.errorMessage
        )
        .onTapGesture(count: 2) { onCancel() }
    }
}

private struct ConfirmHost: View {
    @ObservedObject var state: VoiceOverlayDisplayState
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VoiceConfirmView(
            editingText: $state.editingText,
            originalText: state.pendingText ?? "",
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }
}

// MARK: - Text insertion

private func insertText(_ text: String) {
    let trusted = AXIsProcessTrusted()
    ClLog.voice.debug("[insertText] AXTrusted=\(trusted) text='\(text.prefix(50))'")

    let pb = NSPasteboard.general
    var saved: [(NSPasteboard.PasteboardType, Data)] = []
    for type in pb.types ?? [] {
        if let data = pb.data(forType: type) { saved.append((type, data)) }
    }
    pb.clearContents()
    pb.setString(text, forType: .string)

    guard trusted else {
        ClLog.voice.debug("[insertText] NOT trusted — clipboard only")
        return
    }

    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
    down?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
    up?.flags = .maskCommand
    up?.post(tap: .cghidEventTap)
    ClLog.voice.debug("[insertText] Cmd+V posted")

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        pb.clearContents()
        for (type, data) in saved { pb.setData(data, forType: type) }
    }
}
