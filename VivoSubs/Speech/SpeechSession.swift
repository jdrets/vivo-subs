import AVFoundation
import Foundation
import Speech

enum SpeechSession {
    private static var reservedLocale: Locale?

    static func prepareEnglish() async throws -> (locale: Locale, format: AVAudioFormat) {
        guard SpeechTranscriber.isAvailable else {
            throw CaptionError.speechUnavailable
        }

        let locale = try await resolveEnglishLocale()
        let transcriber = makeTranscriber(locale: locale)

        let status = await AssetInventory.status(forModules: [transcriber])
        if status != .installed {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            } else if status == .unsupported {
                throw CaptionError.englishLocaleUnsupported
            }
        }

        if reservedLocale == nil {
            _ = try await AssetInventory.reserve(locale: locale)
            reservedLocale = locale
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw CaptionError.speechUnavailable
        }

        return (locale, format)
    }

    static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [.etiquetteReplacements],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
    }

    static func release() async {
        guard let locale = reservedLocale else { return }
        reservedLocale = nil
        _ = await AssetInventory.release(reservedLocale: locale)
    }

    private static func resolveEnglishLocale() async throws -> Locale {
        let preferred = Locale(identifier: "en-US")
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: preferred) {
            return match
        }

        let supported = await SpeechTranscriber.supportedLocales
        if let english = supported.first(where: { $0.identifier.lowercased().hasPrefix("en") }) {
            return english
        }

        throw CaptionError.englishLocaleUnsupported
    }
}
