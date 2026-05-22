import Cocoa
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var menuPopover: NSPopover?
    private var mainWindow: NSWindow?
    private var cancellable: AnyCancellable?
    private var approvalCancellable: AnyCancellable?

    private var eventMonitor: Any?
    private var sizeCancellable: AnyCancellable?
    private var bellTimer: Timer?
    private var idleTimer: Timer?
    private var autoSwitchedToNoBlock = false
    private var bellPhase = 0
    private var cachedTerminal: NSImage?
    private var cachedBell: NSImage?
    private static let bellPhases: [CGFloat] = [
        -13, -7, 0, 7, 13, 7, 0, -7,
        -9,  -4, 0, 4,  9, 4, 0, -4,
        0, 0, 0, 0, 0, 0,
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        SessionScanner.shared.start()
        // Sync ~/.claude/settings.json with current blockApprovals preference
        if AppState.shared.isSetupComplete {
            try? ClaudeSettingsManager.install(blockApprovals: AppState.shared.blockApprovals)
        }

        Task {
            do {
                try await HookServer.shared.start()
            } catch {
                await MainActor.run {
                    AppState.shared.serverError = error.localizedDescription
                    AppState.shared.isServerRunning = false
                }
            }
        }

        startIdleMonitor()
        observeSystemEvents()
    }

    private func startIdleMonitor() {
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdleState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func observeSystemEvents() {
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.autoDisableIntercept(reason: .sleep) }
        }
        wsnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.autoEnableIntercept(reason: .wake) }
        }
        wsnc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
            _ in
            MainActor.assumeIsolated {
                guard AppState.shared.pendingAskQuestion != nil,
                      let app = NSWorkspace.shared.frontmostApplication,
                      let id = app.bundleIdentifier,
                      knownTerminalBundleIds.contains(id) else { return }
                AppState.shared.dismissAskQuestion()
            }
        }

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.autoDisableIntercept(reason: .lock) }
        }
        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.autoEnableIntercept(reason: .unlock) }
        }
    }

    private func autoDisableIntercept(reason: InterceptSwitchReason) {
        let state = AppState.shared
        guard state.isSetupComplete, state.blockApprovals, !autoSwitchedToNoBlock else { return }
        autoSwitchedToNoBlock = true
        try? ClaudeSettingsManager.install(blockApprovals: false)
        AppState.shared.logAutoInterceptChange(enabled: false, reason: reason)
    }

    private func autoEnableIntercept(reason: InterceptSwitchReason) {
        guard autoSwitchedToNoBlock else { return }
        autoSwitchedToNoBlock = false
        try? ClaudeSettingsManager.install(blockApprovals: true)
        AppState.shared.logAutoInterceptChange(enabled: true, reason: reason)
    }

    private func checkIdleState() {
        let state = AppState.shared
        guard state.isSetupComplete else { return }
        if !state.blockApprovals {
            autoSwitchedToNoBlock = false
            return
        }
        // UInt32.max is the documented sentinel for "any event type"
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        if idle >= 60 {
            autoDisableIntercept(reason: .idle)
        } else {
            autoEnableIntercept(reason: .active)
        }
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "ClaudeBar")
        button.action = #selector(handleStatusBarClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        statusItem = item

        // Store button so ApprovalWindowController can anchor to it
        StatusBarButtonStore.shared.button = button

        // Keep icon in sync with pending state (approval takes priority over completion)
        cancellable = Publishers.CombineLatest(
            AppState.shared.$approvalQueue,
            AppState.shared.$pendingCompletions
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self, weak button] approvals, completions in
            guard let self, let button else { return }
            button.title = ""
            if !approvals.isEmpty {
                self.startBellAnimation(for: button)
            } else if !completions.isEmpty {
                self.stopBellAnimation(for: button)
                button.image = self.makeDoneBadgeImage()
            } else {
                self.stopBellAnimation(for: button)
            }
        }

        // Close menu dashboard when approval arrives (approval window takes over)
        approvalCancellable = AppState.shared.$approvalQueue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                if !queue.isEmpty {
                    self?.hideMenuPopover()
                }
            }

        // Configure menu popover
        let mp = NSPopover()
        mp.behavior = .applicationDefined
        mp.animates = false
        let hc = NSHostingController(
            rootView: MenuBarView(
                onShowApproval: { [weak self] in
                    self?.hideMenuPopover()
                    ApprovalWindowController.shared.show()
                },
                onOpenSetup:  { [weak self] in self?.openSetupWindow()           },
                onOpenStats:  { [weak self] in self?.hideMenuPopover(); self?.openMainWindow(tab: .stats) }
            )
        )
        mp.contentViewController = hc
        // Track SwiftUI content size changes and resize the popover dynamically
        sizeCancellable = hc.publisher(for: \.preferredContentSize)
            .receive(on: DispatchQueue.main)
            .sink { [weak mp] size in
                guard size.width > 0, size.height > 0 else { return }
                mp?.contentSize = size
            }
        menuPopover = mp
    }

    @objc private func handleStatusBarClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            hideMenuPopover()
            showContextMenu()
        } else {
            toggleMenuPopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Statistics",     action: #selector(menuOpenStats),              keyEquivalent: "")
        menu.addItem(withTitle: "Settings",       action: #selector(menuOpenSettings),           keyEquivalent: "")
        menu.addItem(withTitle: "Activity Log",   action: #selector(menuOpenLog),               keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClaudeBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        // statusItem.menu を一時的にセットして表示後に nil に戻す（左クリックを維持するため）
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func menuOpenStats()    { openMainWindow(tab: .stats)    }
    @objc private func menuOpenSettings() { openMainWindow(tab: .settings) }
    @objc private func menuOpenLog()      { openMainWindow(tab: .log)      }

    private func toggleMenuPopover() {
        guard let mp = menuPopover else { return }
        if mp.isShown { hideMenuPopover() } else { showMenuPopover() }
    }

    private func showMenuPopover() {
        guard let mp = menuPopover, let button = statusItem?.button, !mp.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        mp.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        mp.contentViewController?.view.window?.makeKey()
        AppState.shared.popoverOpenCount += 1
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hideMenuPopover()
        }
    }

    private func hideMenuPopover() {
        menuPopover?.performClose(nil)
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    func openSetupWindow() {
        let w = makeWindow(title: "Setup", size: NSSize(width: 400, height: 380))
        w.contentView = NSHostingView(rootView: SetupView())
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openMainWindow(tab: MainTab = .stats) {
        if mainWindow == nil {
            let w = makeWindow(title: "ClaudeBar", size: NSSize(width: 640, height: 556))
            w.contentView = NSHostingView(rootView: MainWindowView())
            mainWindow = w
        }
        MainWindowState.shared.selectedTab = tab
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(title: String, size: NSSize) -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = title
        w.titleVisibility = .hidden
        w.center()
        w.isReleasedWhenClosed = false
        return w
    }

    private func startBellAnimation(for button: NSButton) {
        guard bellTimer == nil else { return }
        cachedTerminal = Self.loadTerminalImage()
        cachedBell = Self.loadBellImage()

        bellPhase = 0
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self, weak button] _ in
            MainActor.assumeIsolated {
                guard let self, let button else { return }
                self.bellPhase = (self.bellPhase + 1) % Self.bellPhases.count
                button.image = self.makeMenuBarImage(bellAngle: Self.bellPhases[self.bellPhase])
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        bellTimer = timer
        button.image = makeMenuBarImage(bellAngle: 0)
    }

    private func stopBellAnimation(for button: NSButton) {
        bellTimer?.invalidate()
        bellTimer = nil
        bellPhase = 0
        cachedTerminal = nil
        cachedBell = nil
        button.image = makeMenuBarImage(bellAngle: nil)
    }

    private func makeDoneBadgeImage() -> NSImage {
        guard let terminal = cachedTerminal ?? Self.loadTerminalImage() else { return NSImage() }
        let tw = terminal.size.width
        let th = terminal.size.height
        let dot: CGFloat = 5.5
        return composite(on: terminal) { ctx in
            ctx.setFillColor(NSColor.systemGreen.cgColor)
            ctx.fillEllipse(in: CGRect(x: tw - dot, y: th - dot, width: dot, height: dot))
        }
    }

    private func makeMenuBarImage(bellAngle: CGFloat?) -> NSImage {
        guard let terminal = cachedTerminal ?? Self.loadTerminalImage() else { return NSImage() }

        guard let angle = bellAngle else {
            return terminal
        }

        guard let bell = cachedBell ?? Self.loadBellImage() else { return terminal }

        let tw = terminal.size.width
        let th = terminal.size.height
        let bw = bell.size.width
        let bh = bell.size.height
        let pivotX = tw - bw * 0.3
        let pivotY = th - 0.5

        return composite(on: terminal) { ctx in
            ctx.saveGState()
            ctx.translateBy(x: pivotX, y: pivotY)
            ctx.rotate(by: angle * .pi / 180)
            bell.draw(in: NSRect(x: -bw / 2, y: -bh, width: bw, height: bh))
            ctx.restoreGState()
        }
    }

    private func composite(on terminal: NSImage, overlay: @escaping (CGContext) -> Void) -> NSImage {
        let result = NSImage(size: terminal.size, flipped: false) { _ in
            terminal.draw(in: NSRect(origin: .zero, size: terminal.size))
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            overlay(ctx)
            return true
        }
        result.isTemplate = false
        return result
    }

    private static func loadTerminalImage() -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        return NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
    }

    private static func loadBellImage() -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
        return NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        idleTimer?.invalidate(); idleTimer = nil
        Task { await HookServer.shared.stop() }
        ActivityStore.shared.close()
        return .terminateNow
    }
}

// Shared storage for the status bar button so ApprovalWindowController can access it
@MainActor
final class StatusBarButtonStore {
    static let shared = StatusBarButtonStore()
    var button: NSButton?
    private init() {}
}
