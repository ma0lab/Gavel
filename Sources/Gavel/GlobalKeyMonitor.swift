import AppKit

enum CommandPaletteShortcut: String, CaseIterable, Codable {
    case rightOptUp         = "rightOptUp"          // 右 ⌥ + ↑  (default)
    case rightOptRightShift = "rightOptRightShift"  // 右 ⌥ + 右 ⇧

    static let `default` = Self.rightOptUp

    // Right Option = keyCode 61, produces .option flag
    var key1Code: UInt16 { 61 }
    var key1Flag: NSEvent.ModifierFlags { .option }

    // Modifier-key shortcuts: key2 tracked via flagsChanged (no permission needed)
    var key2Code: UInt16? {
        switch self {
        case .rightOptRightShift: return 60
        case .rightOptUp:         return nil
        }
    }
    var key2Flag: NSEvent.ModifierFlags? {
        switch self {
        case .rightOptRightShift: return .shift
        case .rightOptUp:         return nil
        }
    }

    // Regular-key shortcuts: second key detected via global keyDown monitor.
    // Requires Input Monitoring in System Settings > Privacy & Security.
    var regularKeyCode: UInt16? {
        switch self {
        case .rightOptRightShift: return nil
        case .rightOptUp:         return 126 // kVK_UpArrow
        }
    }

    var displayName: String {
        switch self {
        case .rightOptUp:         return "右 ⌥ + ↑"
        case .rightOptRightShift: return "右 ⌥ + 右 ⇧"
        }
    }
}

@MainActor
final class GlobalKeyMonitor: ObservableObject {
    static let shared = GlobalKeyMonitor()

    var shortcut: CommandPaletteShortcut = .default

    var onFire: (() -> Void)?

    private var key1Held = false
    private var key2Held = false
    private var didFire  = false
    private var flagsMonitor: Any?
    private var keyMonitor: Any?

    private init() {}

    func start() {
        guard flagsMonitor == nil else { return }

        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let kc    = event.keyCode
            let flags = event.modifierFlags
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                if kc == self.shortcut.key1Code {
                    self.key1Held = flags.contains(self.shortcut.key1Flag)
                    if !self.key1Held { self.didFire = false }
                }
                if let key2Code = self.shortcut.key2Code, let key2Flag = self.shortcut.key2Flag {
                    if kc == key2Code { self.key2Held = flags.contains(key2Flag) }
                    if self.key1Held && self.key2Held && !self.didFire {
                        self.didFire = true
                        self.onFire?()
                    }
                }
            }
        }

        // For shortcuts with a regular key (e.g. ↑): requires Input Monitoring permission.
        if shortcut.regularKeyCode != nil {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let kc = event.keyCode
                MainActor.assumeIsolated { [weak self] in
                    guard let self,
                          self.key1Held,
                          !self.didFire,
                          kc == self.shortcut.regularKeyCode else { return }
                    self.didFire = true
                    self.onFire?()
                }
            }
        }
    }

    func stop() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = keyMonitor   { NSEvent.removeMonitor(m); keyMonitor = nil }
        key1Held = false
        key2Held = false
        didFire  = false
    }
}
