import SwiftUI

@main
struct VivoSubsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Vivo Subs", systemImage: "captions.bubble.fill") {
            MenuBarContent()
                .environment(CaptionController.shared)
        }
    }
}
