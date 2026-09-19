import AppKit
import AVFoundation
import Foundation
import Observation
import Speech
import Translation

@Observable
@MainActor
final class CaptionController {
    static let shared = CaptionController()

    let translationHub = TranslationHub()

    private(set) var status: SessionStatus = .idle
    private(set) var lines: [CaptionLine] = []
    private(set) var liveEnglish: String = ""
    private(set) var audioLevel: Float = 0
    private(set) var isRunning = false
    private(set) var translationHint: String?
    var showEnglish = true

    private let capture = SystemAudioCapture()
    private let transcriberEngine = LiveTranscriber()
    private var overlay: OverlayPanelController?
    private var pipelineTask: Task<Void, Never>?
    private var runID = UUID()
    private let maxLines = 40

    var translationConfiguration: TranslationSession.Configuration {
        translationHub.configuration
    }

    var canStart: Bool { !isRunning }
    var overlayVisible: Bool { overlay?.isVisible == true }

    func attachOverlay(_ overlay: OverlayPanelController) {
        self.overlay = overlay
    }

    func toggleOverlay() {
        overlay?.toggle()
    }

    func showOverlay() {
        overlay?.show(controller: self)
    }

    func toggleRunning() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        status = .starting
        translationHint = nil
        liveEnglish = ""
        pipelineTask?.cancel()
        let id = UUID()
        runID = id
        pipelineTask = Task { await runPipeline(id) }
    }

    func stop() {
        runID = UUID()
        pipelineTask?.cancel()
        pipelineTask = nil
        Task {
            await transcriberEngine.stop()
            try? await capture.stop()
        }
        isRunning = false
        liveEnglish = ""
        audioLevel = 0
        if case .error = status {
            return
        }
        status = .idle
    }

    func clearHistory() {
        lines.removeAll()
        liveEnglish = ""
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(SystemSettingsURL.screenRecording)
    }

    func openTranslationSettings() {
        NSWorkspace.shared.open(SystemSettingsURL.translation)
    }

    func attachTranslationSession(_ session: TranslationSession) async {
        await translationHub.serve(session)
    }

    private func runPipeline(_ id: UUID) async {
        do {
            let translationStatus = try await translationHub.checkAvailability()
            switch translationStatus {
            case .unsupported:
                throw CaptionError.translationUnsupported
            case .supported:
                translationHint = CaptionError.translationNotInstalled.localizedDescription
            case .installed:
                translationHint = nil
            @unknown default:
                translationHint = nil
            }

            status = .downloadingSpeech
            let prepared = try await transcriberEngine.prepareEnglish()

            status = .starting
            let audio = try await capture.start(preferredFormat: prepared.format)
            try await transcriberEngine.start(
                transcriber: prepared.transcriber,
                format: prepared.format,
                audio: meter(audio)
            )

            status = .listening
            for try await event in transcriberEngine.events(from: prepared.transcriber) {
                try Task.checkCancellation()
                handle(event)
            }
        } catch is CancellationError {
            if runID == id { status = .idle }
        } catch let error as CaptionError {
            if runID == id { status = .error(error.localizedDescription) }
        } catch {
            if runID == id { status = .error(error.localizedDescription) }
        }

        if runID == id {
            await transcriberEngine.stop()
            try? await capture.stop()
            isRunning = false
            audioLevel = 0
            liveEnglish = ""
        }
    }

    private func meter(_ audio: AsyncStream<SendablePCMBuffer>) -> AsyncStream<SendablePCMBuffer> {
        AsyncStream(bufferingPolicy: .bufferingNewest(12)) { continuation in
            let task = Task { @MainActor in
                for await chunk in audio {
                    audioLevel = PCMBuffer.rmsLevel(chunk.buffer)
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func handle(_ event: TranscriptEvent) {
        if event.isFinal {
            liveEnglish = ""
            enqueueFinal(event.text)
        } else {
            liveEnglish = event.text
        }
    }

    private func enqueueFinal(_ english: String) {
        if lines.last?.english == english {
            return
        }

        let line = CaptionLine(english: english)
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }

        Task { [translationHub] in
            do {
                let spanish = try await translationHub.translate(english)
                if let index = lines.firstIndex(where: { $0.id == line.id }) {
                    lines[index].spanish = spanish
                    lines[index].isTranslating = false
                }
            } catch {
                if let index = lines.firstIndex(where: { $0.id == line.id }) {
                    lines[index].spanish = english
                    lines[index].isTranslating = false
                }
            }
        }
    }
}
