import AVFoundation
import Foundation

final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<SendablePCMBuffer>.Continuation?
    private var tapInstalled = false

    func start(preferredFormat _: AVAudioFormat) async throws -> AsyncStream<SendablePCMBuffer> {
        stop()

        let granted = await MediaPermissions.requestMicrophone()
        guard granted else {
            throw CaptionError.microphoneDenied
        }

        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(false)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw CaptionError.microphoneUnavailable
        }

        let audioStream = AsyncStream<SendablePCMBuffer>(bufferingPolicy: .bufferingNewest(12)) { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.continuation = nil
            }
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            guard let copied = PCMBuffer.copy(buffer) else { return }
            self?.continuation?.yield(SendablePCMBuffer(buffer: copied))
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()
        return audioStream
    }

    func stop() {
        continuation?.finish()
        continuation = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        engine.reset()
    }
}
