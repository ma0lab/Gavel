import AppKit
import SwiftUI

@MainActor
final class StatusBarPanel {
    private var panel: NSPanel?
    private let width: CGFloat
    private let height: CGFloat
    private let viewFactory: () -> NSView

    init(width: CGFloat, height: CGFloat, viewFactory: @escaping () -> NSView) {
        self.width = width
        self.height = height
        self.viewFactory = viewFactory
    }

    func show() {
        if panel == nil { createPanel() }
        guard let p = panel else { return }
        position(p)
        guard !p.isVisible else { return }
        p.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func position(_ p: NSPanel) {
        guard let button = StatusBarButtonStore.shared.button,
              let buttonWindow = button.window else { return }
        let buttonScreenFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonScreenFrame.midX - width / 2
        let y = buttonScreenFrame.minY - height - 6
        if let screen = buttonWindow.screen ?? NSScreen.main {
            x = max(screen.visibleFrame.minX, min(x, screen.visibleFrame.maxX - width))
        }
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func createPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = viewFactory()
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.autoresizingMask = [.width, .height]
        p.contentView = view
        self.panel = p
    }
}
