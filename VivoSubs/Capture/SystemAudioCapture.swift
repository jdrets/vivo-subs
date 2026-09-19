import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var continuation: AsyncStream<SendablePCMBuffer>.Continuation?
    private var converter: AudioFormatConverter?
    private let handlerQueue = DispatchQueue(label: "com.juliandrets.vivo-subs.audio", qos: .userInitiated)

    func start(preferredFormat: AVAudioFormat) async throws -> AsyncStream<SendablePCMBuffer> {
        try await stop()

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptionError.screenRecordingDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptionError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.channelCount = Int(preferredFormat.channelCount)
        configuration.sampleRate = Int(preferredFormat.sampleRate.rounded())
        configuration.width = 8
        configuration.height = 8
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.queueDepth = 3

        let captureStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try captureStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: handlerQueue)

        let audioStream = AsyncStream<SendablePCMBuffer>(bufferingPolicy: .bufferingNewest(12)) { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.continuation = nil
            }
        }

        try await captureStream.startCapture()
        stream = captureStream
        return audioStream
    }

    func stop() async throws {
        continuation?.finish()
        continuation = nil
        converter = nil
        if let stream {
            try await stream.stopCapture()
        }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let original = PCMBuffer.make(from: sampleBuffer),
              let copied = PCMBuffer.copy(original) else {
            return
        }
        continuation?.yield(SendablePCMBuffer(buffer: copied))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        continuation?.finish()
        continuation = nil
    }
}
