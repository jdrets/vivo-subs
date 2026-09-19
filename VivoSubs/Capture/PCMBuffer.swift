import AVFoundation
import Darwin
import Foundation

enum PCMBuffer {
    static func make(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = sampleBuffer.formatDescription,
              var asbd = formatDescription.audioStreamBasicDescription,
              let format = AVAudioFormat(streamDescription: &asbd) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }

    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copied = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }
        copied.frameLength = buffer.frameLength
        let byteCount = Int(buffer.frameLength)

        if let src = buffer.floatChannelData, let dst = copied.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                memcpy(dst[channel], src[channel], byteCount * MemoryLayout<Float>.size)
            }
            return copied
        }

        if let src = buffer.int16ChannelData, let dst = copied.int16ChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                memcpy(dst[channel], src[channel], byteCount * MemoryLayout<Int16>.size)
            }
            return copied
        }

        if let src = buffer.int32ChannelData, let dst = copied.int32ChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                memcpy(dst[channel], src[channel], byteCount * MemoryLayout<Int32>.size)
            }
            return copied
        }

        return nil
    }

    static func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        if let data = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frames {
                let sample = data[i]
                sum += sample * sample
            }
            return min(1, sqrt(sum / Float(frames)) * 8)
        }

        if let data = buffer.int16ChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frames {
                let sample = Float(data[i]) / Float(Int16.max)
                sum += sample * sample
            }
            return min(1, sqrt(sum / Float(frames)) * 8)
        }

        return 0
    }
}

struct SendablePCMBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

final class AudioFormatConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init?(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        guard inputFormat != outputFormat else { return nil }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        self.converter = converter
        self.outputFormat = outputFormat
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if input.format == outputFormat {
            return input
        }

        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: max(capacity, 1)) else {
            return input
        }

        var conversionError: NSError?
        var didSupply = false
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if didSupply {
                outStatus.pointee = .noDataNow
                return nil
            }
            didSupply = true
            outStatus.pointee = .haveData
            return input
        }

        if let conversionError {
            throw conversionError
        }
        guard status != .error else { return input }
        return output
    }
}
