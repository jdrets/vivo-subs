import Foundation

enum CaptionError: LocalizedError {
    case speechUnavailable
    case englishLocaleUnsupported
    case screenRecordingDenied
    case noDisplay
    case translationUnsupported
    case translationNotInstalled
    case captureFailed(String)
    case speechFailed(String)

    var errorDescription: String? {
        switch self {
        case .speechUnavailable:
            return "La transcripción on-device no está disponible en esta Mac."
        case .englishLocaleUnsupported:
            return "Este sistema no tiene un modelo de voz en inglés."
        case .screenRecordingDenied:
            return "Falta el permiso de Grabación de pantalla. Sin eso la app no puede oír Zoom, Meet o Teams."
        case .noDisplay:
            return "No encontré una pantalla para capturar audio del sistema."
        case .translationUnsupported:
            return "Esta Mac no puede traducir de inglés a español on-device."
        case .translationNotInstalled:
            return "Falta el pack de traducción inglés → español. Instalálo en Ajustes del Sistema."
        case .captureFailed(let message):
            return "No pude capturar el audio del sistema: \(message)"
        case .speechFailed(let message):
            return "Falló la transcripción: \(message)"
        }
    }
}

enum SessionStatus: Equatable {
    case idle
    case starting
    case downloadingSpeech
    case listening
    case error(String)

    var label: String {
        switch self {
        case .idle:
            return "En espera"
        case .starting:
            return "Preparando…"
        case .downloadingSpeech:
            return "Descargando modelo de voz…"
        case .listening:
            return "Escuchando audio del sistema"
        case .error(let message):
            return message
        }
    }
}

struct CaptionLine: Identifiable, Equatable {
    let id: UUID
    let english: String
    var spanish: String
    var isTranslating: Bool

    init(english: String, spanish: String = "", isTranslating: Bool = true) {
        self.id = UUID()
        self.english = english
        self.spanish = spanish
        self.isTranslating = isTranslating
    }
}

enum SystemSettingsURL {
    static let screenRecording = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!
    static let translation = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings")!
}
