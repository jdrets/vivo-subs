import AVFoundation
import Foundation
import Speech

struct TranscriptEvent: Sendable {
    let text: String
    let isFinal: Bool
}

final class LiveTranscriber: @unchecked Sendable {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var reservedLocale: Locale?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?

    func prepareEnglish() async throws -> (transcriber: SpeechTranscriber, format: AVAudioFormat) {
        guard SpeechTranscriber.isAvailable else {
            throw CaptionError.speechUnavailable
        }

        let locale = try await Self.resolveEnglishLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [.etiquetteReplacements],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )

        let status = await AssetInventory.status(forModules: [transcriber])
        if status != .installed {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            } else if status == .unsupported {
                throw CaptionError.englishLocaleUnsupported
            }
        }

        _ = try await AssetInventory.reserve(locale: locale)
        reservedLocale = locale

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw CaptionError.speechUnavailable
        }

        self.transcriber = transcriber
        return (transcriber, format)
    }

    func start(
        transcriber: SpeechTranscriber,
        format: AVAudioFormat,
        audio: AsyncStream<SendablePCMBuffer>
    ) async throws {
        let (inputSequence, builder) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        inputBuilder = builder

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        self.analyzer = analyzer
        try await analyzer.start(inputSequence: inputSequence)

        Task.detached { [weak self] in
            var converter: AudioFormatConverter?
            for await chunk in audio {
                guard let self, let builder = self.inputBuilder else { break }
                let buffer = chunk.buffer
                let converted: AVAudioPCMBuffer
                if buffer.format == format {
                    converted = buffer
                } else {
                    if converter == nil {
                        converter = AudioFormatConverter(from: buffer.format, to: format)
                    }
                    do {
                        converted = try converter?.convert(buffer) ?? buffer
                    } catch {
                        continue
                    }
                }
                builder.yield(AnalyzerInput(buffer: converted))
            }
            self?.inputBuilder?.finish()
        }
    }

    func events(from transcriber: SpeechTranscriber) -> AsyncThrowingStream<TranscriptEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await result in transcriber.results {
                        let text = NSAttributedString(result.text).string
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        continuation.yield(TranscriptEvent(text: text, isFinal: result.isFinal))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func stop() async {
        inputBuilder?.finish()
        inputBuilder = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        analyzer = nil
        transcriber = nil
        if let reservedLocale {
            _ = await AssetInventory.release(reservedLocale: reservedLocale)
        }
        reservedLocale = nil
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
