import Cocoa
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var menuPopover: NSPopover?
    private var cancellable: AnyCancellable?
    private var approvalCancellable: AnyCancellable?

    private var bellTimer: Timer?
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
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "ClaudeBar")
        button.action = #selector(handleStatusBarClick)
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

        // Close menu popover when approval arrives so they don't conflict
        approvalCancellable = AppState.shared.$approvalQueue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                if !queue.isEmpty {
                    self?.menuPopover?.performClose(nil)
                }
            }

        // Configure menu popover
        let mp = NSPopover()
        mp.contentSize = NSSize(width: 320, height: 400)
        mp.behavior = .transient
        mp.animates = true
        mp.contentViewController = NSHostingController(
            rootView: MenuBarView(
                onShowApproval: { [weak self, weak mp] in
                    mp?.performClose(nil)
                    ApprovalWindowController.shared.show()
                },
                onOpenSetup: { [weak self] in self?.openSetupWindow() },
                onOpenSettings: { [weak self] in self?.openSettingsWindow() },
                onOpenLog: { [weak self] in self?.openLogWindow() }
            )
        )
        menuPopover = mp
    }

    @objc private func handleStatusBarClick() {
        toggleMenuPopover()
    }

    private func toggleMenuPopover() {
        guard let mp = menuPopover, let button = statusItem?.button else { return }
        if mp.isShown {
            mp.performClose(nil)
        } else {
            mp.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func openSetupWindow() {
        let w = makeWindow(title: "Setup", size: NSSize(width: 400, height: 380))
        w.contentView = NSHostingView(rootView: SetupView())
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettingsWindow() {
        let w = makeWindow(title: "Settings", size: NSSize(width: 400, height: 340))
        w.contentView = NSHostingView(rootView: SettingsView())
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openLogWindow() {
        let w = makeWindow(title: "Activity Log", size: NSSize(width: 480, height: 360))
        w.contentView = NSHostingView(rootView: LogView())
        w.makeKeyAndOrderFront(nil)
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
        w.center()
        w.isReleasedWhenClosed = false
        return w
    }

    private func makeDoneBadgeImage() -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        guard let terminal = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return NSImage() }

        let tw = terminal.size.width
        let th = terminal.size.height
        let dot: CGFloat = 5.5
        let canvas = NSSize(width: tw + dot * 0.4, height: th)

        let result = NSImage(size: canvas, flipped: false) { _ in
            terminal.draw(in: NSRect(origin: .zero, size: terminal.size))
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.setFillColor(NSColor.systemGreen.cgColor)
            ctx.fillEllipse(in: CGRect(x: tw - dot * 0.5, y: th - dot - 0.5, width: dot, height: dot))
            return true
        }
        result.isTemplate = false
        return result
    }

    private func startBellAnimation(for button: NSButton) {
        guard bellTimer == nil else { return }
        // アニメーション中に毎フレーム SF Symbol を再生成しないようキャッシュ
        let termCfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        cachedTerminal = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(termCfg)
        let bellCfg = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
        cachedBell = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(bellCfg)

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

    private func makeMenuBarImage(bellAngle: CGFloat?) -> NSImage {
        guard let angle = bellAngle else {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            return NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) ?? NSImage()
        }

        let termCfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        guard let terminal = cachedTerminal ?? NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(termCfg) else { return NSImage() }

        let bellCfg = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
        guard let bell = cachedBell ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(bellCfg) else { return terminal }

        let tw = terminal.size.width
        let th = terminal.size.height
        let bw = bell.size.width
        let bh = bell.size.height

        // ベルの吊り下げ点: ターミナルの右 60% 付近に重なる
        let pivotX = tw * 0.62
        let canvasW = tw + bw * 1.5   // 音波アーク分の余白
        let canvasH = max(th, bh * 1.4)

        let result = NSImage(size: NSSize(width: canvasW, height: canvasH), flipped: false) { _ in
            terminal.draw(in: NSRect(x: 0, y: (canvasH - th) / 2, width: tw, height: th))

            let ctx = NSGraphicsContext.current!.cgContext

            let pivotY = canvasH * 0.90
            // ベル中心 (音波の基点)
            let bellCenter = CGPoint(x: pivotX, y: pivotY - bh * 0.5)

            // 音波アーク: ベル右側に 2 本
            let waves: [(CGFloat, CGFloat)] = [(bw * 0.85, 0.85), (bw * 1.45, 0.45)]
            for (r, alpha) in waves {
                ctx.setStrokeColor(NSColor.systemOrange.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(0.8)
                ctx.setLineCap(.round)
                ctx.beginPath()
                ctx.addArc(center: bellCenter, radius: r,
                           startAngle: -.pi * 0.32,
                           endAngle:    .pi * 0.32,
                           clockwise: false)
                ctx.strokePath()
            }

            // ベル（回転あり）
            ctx.saveGState()
            ctx.translateBy(x: pivotX, y: pivotY)
            ctx.rotate(by: angle * .pi / 180)
            bell.draw(in: NSRect(x: -bw / 2, y: -bh, width: bw, height: bh))
            ctx.restoreGState()

            return true
        }
        result.isTemplate = false
        return result
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { await HookServer.shared.stop() }
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
