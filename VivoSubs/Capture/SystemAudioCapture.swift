import AVFoundation
import CoreAudio
import Darwin
import Foundation

/// Captures what the Mac is playing via a Core Audio process tap.
/// That uses "System Audio Recording Only", not Screen Recording.
final class SystemAudioCapture: @unchecked Sendable {
    private var continuation: AsyncStream<SendablePCMBuffer>.Continuation?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "com.juliandrets.vivo-subs.system-audio", qos: .userInitiated)

    func start(preferredFormat _: AVAudioFormat) async throws -> AsyncStream<SendablePCMBuffer> {
        try await stop()

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "Vivo Subs"
        tapDescription.uuid = UUID()
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &tap)
        guard status == noErr else {
            throw CaptionError.systemAudioDenied
        }
        tapID = tap

        let outputUID = try CoreAudioSupport.defaultOutputDeviceUID()
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vivo Subs Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        var aggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate)
        guard status == noErr else {
            try await stop()
            throw CaptionError.captureFailed("CreateAggregateDevice (\(status))")
        }
        aggregateID = aggregate

        var asbd = try CoreAudioSupport.tapStreamFormat(tap)
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            try await stop()
            throw CaptionError.captureFailed("formato de audio del tap inválido")
        }

        let (audioStream, continuation) = AsyncStream.makeStream(
            of: SendablePCMBuffer.self,
            bufferingPolicy: .bufferingNewest(12)
        )
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            self?.continuation = nil
        }

        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, ioQueue) { _, inInputData, _, _, _ in
            guard let buffer = Self.pcmBuffer(format: format, from: inInputData),
                  let copied = PCMBuffer.copy(buffer) else {
                return
            }
            continuation.yield(SendablePCMBuffer(buffer: copied))
        }
        guard status == noErr, let procID else {
            try await stop()
            throw CaptionError.captureFailed("CreateIOProc (\(status))")
        }
        ioProcID = procID

        status = AudioDeviceStart(aggregate, procID)
        guard status == noErr else {
            try await stop()
            throw CaptionError.systemAudioDenied
        }

        return audioStream
    }

    func stop() async throws {
        continuation?.finish()
        continuation = nil

        if let procID = ioProcID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            ioProcID = nil
        }
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private static func pcmBuffer(
        format: AVAudioFormat,
        from inputData: UnsafePointer<AudioBufferList>
    ) -> AVAudioPCMBuffer? {
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let first = source.first, first.mDataByteSize > 0 else { return nil }

        let bytesPerFrame = max(1, format.streamDescription.pointee.mBytesPerFrame)
        let frames = AVAudioFrameCount(first.mDataByteSize / bytesPerFrame)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames

        let destination = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for index in 0..<min(source.count, destination.count) {
            guard let src = source[index].mData, let dst = destination[index].mData else { continue }
            let byteCount = Int(min(source[index].mDataByteSize, destination[index].mDataByteSize))
            memcpy(dst, src, byteCount)
        }
        return buffer
    }
}
