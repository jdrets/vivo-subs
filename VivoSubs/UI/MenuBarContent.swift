import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(CaptionController.self) private var controller

    var body: some View {
        Button(controller.isRunning ? "Detener subtítulos" : "Iniciar subtítulos") {
            controller.showOverlay()
            controller.toggleRunning()
        }

        Button(controller.overlayVisible ? "Ocultar ventana" : "Mostrar ventana") {
            controller.toggleOverlay()
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])

        Toggle("Mostrar inglés original", isOn: Binding(
            get: { controller.showEnglish },
            set: { controller.showEnglish = $0 }
        ))

        Divider()

        Button("Abrir permiso de pantalla…") {
            controller.openScreenRecordingSettings()
        }

        Button("Abrir packs de traducción…") {
            controller.openTranslationSettings()
        }

        Button("Limpiar historial") {
            controller.clearHistory()
        }

        Divider()

        Button("Salir de Vivo Subs") {
            controller.stop()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
