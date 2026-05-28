import AppKit

enum VoiceTriggerKey: String, CaseIterable, Codable {
    case rightCommand = "rightCommand"
    case rightControl = "rightControl"
    case rightOption  = "rightOption"

    var keyCode: UInt16 {
        switch self {
        case .rightCommand: return 54
        case .rightControl: return 62
        case .rightOption:  return 61
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand: return .command
        case .rightControl: return .control
        case .rightOption:  return .option
        }
    }

    var displayName: String {
        switch self {
        case .rightCommand: return "右 ⌘ Command"
        case .rightControl: return "右 ⌃ Control"
        case .rightOption:  return "右 ⌥ Option"
        }
    }
}

// PTT (Push-To-Talk) monitor using NSEvent.addGlobalMonitorForEvents(.flagsChanged).
// No Accessibility or Input Monitoring permission required.
@MainActor
final class VoicePTTMonitor {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var triggerKey: VoiceTriggerKey = .rightCommand

    private let log = ClLog.voice
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var holdTimer: Timer?
    private var isRecording = false
    private static let holdThreshold: TimeInterval = 0.4

    func start() {
        guard globalMonitor == nil else { return }
        log.debug("PTTMonitor start: key=\(triggerKey.rawValue)")
        // Global: fires when another app is frontmost
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.handleFlagsChanged(keyCode: keyCode, flags: flags) }
        }
        // Local: fires when ClaudeBar itself is frontmost (e.g. approval panel showing)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.handleFlagsChanged(keyCode: keyCode, flags: flags) }
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor  = nil }
        holdTimer?.invalidate()
        holdTimer = nil
        isRecording = false
    }

    private func handleFlagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard keyCode == triggerKey.keyCode else { return }
        let isPressed = flags.contains(triggerKey.flag)

        if isPressed {
            guard holdTimer == nil, !isRecording else { return }
            log.debug("PTT keyDown: waiting \(Self.holdThreshold)s threshold")
            let timer = Timer(timeInterval: Self.holdThreshold, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.holdTimer = nil
                    self.isRecording = true
                    self.log.info("PTT start recording")
                    self.onStart?()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            holdTimer = timer
        } else {
            holdTimer?.invalidate()
            holdTimer = nil
            if isRecording {
                isRecording = false
                log.info("PTT stop recording")
                onStop?()
            } else {
                log.debug("PTT keyUp: released before threshold (no recording)")
            }
        }
    }
}
