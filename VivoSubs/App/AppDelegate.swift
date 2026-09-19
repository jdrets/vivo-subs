import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayPanelController()
    private let hotKeys = HotKeyMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        CaptionController.shared.attachOverlay(overlay)
        overlay.show(controller: CaptionController.shared)

        hotKeys.onToggleOverlay = { [weak overlay] in
            overlay?.toggle()
        }
        hotKeys.register()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
