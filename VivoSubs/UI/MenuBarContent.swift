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

        Toggle("Transcribir audio", isOn: Binding(
            get: { controller.transcribeSystemAudio },
            set: { controller.transcribeSystemAudio = $0 }
        ))

        Toggle("Transcribir mi voz", isOn: Binding(
            get: { controller.transcribeMyVoice },
            set: { controller.transcribeMyVoice = $0 }
        ))

        Toggle("Mostrar inglés original", isOn: Binding(
            get: { controller.showEnglish },
            set: { controller.showEnglish = $0 }
        ))

        Divider()

        Button("Abrir permiso de audio del sistema…") {
            controller.openSystemAudioSettings()
        }

        Button("Abrir permiso de micrófono…") {
            controller.openMicrophoneSettings()
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
