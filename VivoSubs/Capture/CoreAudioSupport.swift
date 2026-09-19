import CoreAudio
import Foundation

enum CoreAudioSupport {
    static func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func property<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        as type: T.Type,
        op: String
    ) throws -> T {
        var address = propertyAddress(selector)
        var dataSize = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, pointer)
        guard status == noErr else {
            throw CaptionError.captureFailed("\(op) (\(status))")
        }
        return pointer.pointee
    }

    static func stringProperty(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        op: String
    ) throws -> String {
        var address = propertyAddress(selector)
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(object, &address, 0, nil, &dataSize)
        guard status == noErr else {
            throw CaptionError.captureFailed("\(op) size (\(status))")
        }

        let pointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        pointer.initialize(to: nil)
        defer { pointer.deinitialize(count: 1); pointer.deallocate() }
        status = AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, pointer)
        guard status == noErr, let cfString = pointer.pointee else {
            throw CaptionError.captureFailed("\(op) (\(status))")
        }
        return cfString as String
    }

    static func defaultOutputDeviceUID() throws -> String {
        let deviceID: AudioDeviceID = try property(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDefaultOutputDevice,
            as: AudioDeviceID.self,
            op: "DefaultOutputDevice"
        )
        return try stringProperty(deviceID, kAudioDevicePropertyDeviceUID, op: "OutputDeviceUID")
    }

    static func tapStreamFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        try property(tap, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self, op: "TapFormat")
    }
}
