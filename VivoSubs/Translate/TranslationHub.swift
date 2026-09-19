import Foundation
import Translation

@MainActor
final class TranslationHub {
    let configuration = TranslationSession.Configuration(
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "es")
    )

    private var session: TranslationSession?
    private var serveTask: Task<Void, Never>?

    var sourceLanguage: Locale.Language { Locale.Language(identifier: "en") }
    var targetLanguage: Locale.Language { Locale.Language(identifier: "es") }

    func checkAvailability() async throws -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
    }

    func serve(_ session: TranslationSession) async {
        self.session = session
        try? await session.prepareTranslation()
        serveTask?.cancel()
        await withTaskCancellationHandler {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3_600))
            }
        } onCancel: {
            session.cancel()
        }
    }

    func translate(_ english: String) async throws -> String {
        let trimmed = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let session, await session.isReady {
            let response = try await session.translate(trimmed)
            return response.targetText
        }

        let installed = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        try await installed.prepareTranslation()
        session = installed
        let response = try await installed.translate(trimmed)
        return response.targetText
    }
}
