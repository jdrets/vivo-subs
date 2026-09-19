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
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?

    func start(
        locale: Locale,
        format: AVAudioFormat,
        audio: AsyncStream<SendablePCMBuffer>
    ) async throws {
        let transcriber = SpeechSession.makeTranscriber(locale: locale)
        self.transcriber = transcriber

        let (inputSequence, builder) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        inputBuilder = builder

        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        )
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

    func events() -> AsyncThrowingStream<TranscriptEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let transcriber else {
                continuation.finish()
                return
            }

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
    }
}
