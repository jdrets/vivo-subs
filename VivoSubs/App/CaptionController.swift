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
    private(set) var liveSystemEnglish: String = ""
    private(set) var liveMicrophoneEnglish: String = ""
    private(set) var audioLevel: Float = 0
    private(set) var microphoneLevel: Float = 0
    private(set) var isRunning = false
    private(set) var microphoneEnabled = false
    private(set) var translationHint: String?
    private(set) var microphoneHint: String?
    var showEnglish = true
    var transcribeMyVoice: Bool {
        didSet {
            UserDefaults.standard.set(transcribeMyVoice, forKey: "transcribeMyVoice")
            Task { await applyMicrophonePreference() }
        }
    }

    private let capture = SystemAudioCapture()
    private let microphoneCapture = MicrophoneCapture()
    private let systemTranscriber = LiveTranscriber()
    private let microphoneTranscriber = LiveTranscriber()
    private var overlay: OverlayPanelController?
    private var pipelineTask: Task<Void, Never>?
    private var microphoneListenTask: Task<Void, Never>?
    private var runID = UUID()
    private let maxLines = 40
    private var sessionLocale: Locale?
    private var sessionFormat: AVAudioFormat?

    private init() {
        transcribeMyVoice = UserDefaults.standard.bool(forKey: "transcribeMyVoice")
    }

    var translationConfiguration: TranslationSession.Configuration {
        translationHub.configuration
    }

    var canStart: Bool { !isRunning }
    var overlayVisible: Bool { overlay?.isVisible == true }
    var hasLiveText: Bool { !liveSystemEnglish.isEmpty || !liveMicrophoneEnglish.isEmpty }
    var statusLabel: String {
        if case .listening = status {
            return microphoneEnabled ? "Escuchando sistema y micrófono" : "Escuchando audio del sistema"
        }
        return status.label
    }

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
        microphoneHint = nil
        microphoneEnabled = false
        liveSystemEnglish = ""
        liveMicrophoneEnglish = ""
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
            await teardownCapture()
        }
        isRunning = false
        liveSystemEnglish = ""
        liveMicrophoneEnglish = ""
        audioLevel = 0
        microphoneLevel = 0
        microphoneEnabled = false
        if case .error = status {
            return
        }
        status = .idle
    }

    func clearHistory() {
        lines.removeAll()
        liveSystemEnglish = ""
        liveMicrophoneEnglish = ""
    }

    func openSystemAudioSettings() {
        NSWorkspace.shared.open(SystemSettingsURL.systemAudio)
    }

    func openMicrophoneSettings() {
        NSWorkspace.shared.open(SystemSettingsURL.microphone)
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
            let prepared = try await SpeechSession.prepareEnglish()
            sessionLocale = prepared.locale
            sessionFormat = prepared.format

            status = .starting
            let systemAudio = try await capture.start(preferredFormat: prepared.format)
            try await systemTranscriber.start(
                locale: prepared.locale,
                format: prepared.format,
                audio: meter(systemAudio, source: .system)
            )

            status = .listening
            if transcribeMyVoice {
                await enableMicrophoneIfNeeded()
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                let system = systemTranscriber
                group.addTask {
                    for try await event in system.events() {
                        try Task.checkCancellation()
                        await self.handle(event, source: .system)
                    }
                }
                try await group.waitForAll()
            }
        } catch is CancellationError {
            if runID == id { status = .idle }
        } catch let error as CaptionError {
            if runID == id { status = .error(error.localizedDescription) }
        } catch {
            if runID == id { status = .error(error.localizedDescription) }
        }

        if runID == id {
            await teardownCapture()
            isRunning = false
            audioLevel = 0
            microphoneLevel = 0
            liveSystemEnglish = ""
            liveMicrophoneEnglish = ""
            sessionLocale = nil
            sessionFormat = nil
        }
    }

    private func applyMicrophonePreference() async {
        guard isRunning else { return }
        if transcribeMyVoice {
            await enableMicrophoneIfNeeded()
        } else {
            await disableMicrophone()
        }
    }

    private func enableMicrophoneIfNeeded() async {
        guard transcribeMyVoice, isRunning, !microphoneEnabled else { return }
        guard let locale = sessionLocale, let format = sessionFormat else { return }

        let allowed = await MediaPermissions.requestMicrophone()
        guard transcribeMyVoice, isRunning else { return }
        guard allowed else {
            microphoneHint = CaptionError.microphoneDenied.localizedDescription
            return
        }

        microphoneHint = nil
        guard let microphoneAudio = await startMicrophone(format: format) else { return }
        guard transcribeMyVoice, isRunning else {
            microphoneCapture.stop()
            return
        }

        do {
            try await microphoneTranscriber.start(
                locale: locale,
                format: format,
                audio: meter(microphoneAudio, source: .microphone)
            )
        } catch {
            microphoneHint = error.localizedDescription
            microphoneCapture.stop()
            return
        }

        guard transcribeMyVoice, isRunning else {
            await microphoneTranscriber.stop()
            microphoneCapture.stop()
            return
        }

        microphoneEnabled = true
        let microphone = microphoneTranscriber
        microphoneListenTask = Task.detached {
            do {
                for try await event in microphone.events() {
                    try Task.checkCancellation()
                    await self.handle(event, source: .microphone)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.microphoneHint = error.localizedDescription
                    self.microphoneEnabled = false
                }
            }
        }
    }

    private func disableMicrophone() async {
        microphoneListenTask?.cancel()
        microphoneListenTask = nil
        await microphoneTranscriber.stop()
        microphoneCapture.stop()
        microphoneEnabled = false
        liveMicrophoneEnglish = ""
        microphoneLevel = 0
        microphoneHint = nil
    }

    private func startMicrophone(format: AVAudioFormat) async -> AsyncStream<SendablePCMBuffer>? {
        do {
            return try await microphoneCapture.start(preferredFormat: format)
        } catch let error as CaptionError {
            microphoneHint = error.localizedDescription
            return nil
        } catch {
            microphoneHint = error.localizedDescription
            return nil
        }
    }

    private func teardownCapture() async {
        microphoneListenTask?.cancel()
        microphoneListenTask = nil
        await systemTranscriber.stop()
        await microphoneTranscriber.stop()
        microphoneCapture.stop()
        try? await capture.stop()
        await SpeechSession.release()
        sessionLocale = nil
        sessionFormat = nil
    }

    private func meter(
        _ audio: AsyncStream<SendablePCMBuffer>,
        source: CaptionSource
    ) -> AsyncStream<SendablePCMBuffer> {
        AsyncStream(bufferingPolicy: .bufferingNewest(12)) { continuation in
            let task = Task { @MainActor in
                for await chunk in audio {
                    let level = PCMBuffer.rmsLevel(chunk.buffer)
                    switch source {
                    case .system:
                        audioLevel = level
                    case .microphone:
                        microphoneLevel = level
                    }
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func handle(_ event: TranscriptEvent, source: CaptionSource) {
        if event.isFinal {
            switch source {
            case .system:
                liveSystemEnglish = ""
            case .microphone:
                liveMicrophoneEnglish = ""
            }
            enqueueFinal(event.text, source: source)
        } else {
            switch source {
            case .system:
                liveSystemEnglish = event.text
            case .microphone:
                liveMicrophoneEnglish = event.text
            }
        }
    }

    private func enqueueFinal(_ english: String, source: CaptionSource) {
        if lines.last(where: { $0.source == source })?.english == english {
            return
        }

        let line = CaptionLine(source: source, english: english)
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
