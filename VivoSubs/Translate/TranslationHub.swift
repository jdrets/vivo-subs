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
    private let maxContextSentences = 2

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

    func translate(_ english: String, previous: [String] = []) async throws -> String {
        let current = Self.normalize(english)
        guard !current.isEmpty else { return "" }

        let context = previous.suffix(maxContextSentences).map(Self.normalize).filter { !$0.isEmpty }
        guard !context.isEmpty else {
            return try await translateRaw(current)
        }

        let parts = Array(context) + [current]
        let numbered = parts.enumerated()
            .map { index, text in "\(index + 1). \(text)" }
            .joined(separator: "\n")
        let translated = try await translateRaw(numbered)

        if let currentSpanish = Self.extractCurrent(from: translated, partCount: parts.count) {
            return currentSpanish
        }

        return try await translateRaw(current)
    }

    private func translateRaw(_ english: String) async throws -> String {
        if let session, await session.isReady {
            let response = try await session.translate(english)
            return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let installed = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        try await installed.prepareTranslation()
        session = installed
        let response = try await installed.translate(english)
        return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractCurrent(from translated: String, partCount: Int) -> String? {
        let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, partCount >= 2 else { return nil }

        let numbered = numberedSegments(in: trimmed)
        if numbered.count >= 2, let last = numbered.last, !last.isEmpty {
            return last
        }

        let lines = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count >= 2, let last = lines.last {
            return stripLeadingIndex(last)
        }

        let sentences = sentences(in: trimmed)
        if sentences.count >= 2, let last = sentences.last, !last.isEmpty {
            return last
        }

        return nil
    }

    private static func numberedSegments(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\d{1,2}[\.\)\:]\s+"#) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard matches.count >= 2 else { return [] }

        return matches.enumerated().compactMap { index, match in
            let start = match.range.upperBound
            let end = index + 1 < matches.count ? matches[index + 1].range.location : nsText.length
            guard start < end else { return nil }
            let piece = nsText.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return piece.isEmpty ? nil : piece
        }
    }

    private static func sentences(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<=[.!?…])\s+"#) else {
            return [text]
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return [text] }

        var sentences: [String] = []
        var cursor = 0
        for match in matches {
            let piece = nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                sentences.append(piece)
            }
            cursor = match.range.upperBound
        }
        let tail = nsText.substring(from: cursor).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            sentences.append(tail)
        }
        return sentences
    }

    private static func stripLeadingIndex(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^\d{1,2}[\.\)\:]\s+"#),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        else {
            return text
        }
        return (text as NSString).substring(from: match.range.upperBound)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
