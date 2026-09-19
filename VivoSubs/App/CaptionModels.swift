import Foundation

enum CaptionError: LocalizedError {
    case speechUnavailable
    case englishLocaleUnsupported
    case systemAudioDenied
    case translationUnsupported
    case translationNotInstalled
    case captureFailed(String)
    case speechFailed(String)
    case microphoneDenied
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .speechUnavailable:
            return "La transcripción on-device no está disponible en esta Mac."
        case .englishLocaleUnsupported:
            return "Este sistema no tiene un modelo de voz en inglés."
        case .systemAudioDenied:
            return "Falta el permiso de audio del sistema. En Ajustes → Privacidad → Screen & System Audio Recording, sección “System Audio Recording Only”, activá VivoSubs."
        case .translationUnsupported:
            return "Esta Mac no puede traducir de inglés a español on-device."
        case .translationNotInstalled:
            return "Falta el pack de traducción inglés → español. Instalálo en Ajustes del Sistema."
        case .captureFailed(let message):
            return "No pude capturar el audio del sistema: \(message)"
        case .speechFailed(let message):
            return "Falló la transcripción: \(message)"
        case .microphoneDenied:
            return "Falta el permiso de Micrófono. Sin eso no puedo transcribir lo que decís."
        case .microphoneUnavailable:
            return "No encontré un micrófono disponible."
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
            return "Escuchando sistema y micrófono"
        case .error(let message):
            return message
        }
    }
}

enum CaptionSource: String, Equatable {
    case system
    case microphone
}

struct CaptionLine: Identifiable, Equatable {
    let id: UUID
    let source: CaptionSource
    let english: String
    var spanish: String
    var isTranslating: Bool

    init(source: CaptionSource, english: String, spanish: String = "", isTranslating: Bool = true) {
        self.id = UUID()
        self.source = source
        self.english = english
        self.spanish = spanish
        self.isTranslating = isTranslating
    }
}

enum SystemSettingsURL {
    static let systemAudio = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!
    static let microphone = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")!
    static let translation = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings")!
}
