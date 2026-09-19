import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayPanelController: NSObject, NSWindowDelegate {
    private var panel: OverlayPanel?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show(controller: CaptionController) {
        if panel == nil {
            let hosting = NSHostingView(rootView: CaptionOverlayView().environment(controller))
            hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 320)

            let panel = OverlayPanel(
                contentRect: hosting.frame,
                styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "Vivo Subs"
            panel.titleVisibility = .visible
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.sharingType = .none
            panel.delegate = self
            panel.contentView = hosting
            self.panel = panel
            positionOnScreen(panel)
        }

        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func positionOnScreen(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 48
        )
        panel.setFrameOrigin(origin)
    }
}
