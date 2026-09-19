import AVFoundation
import Foundation

enum MediaPermissions {
    @MainActor
    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return await AVCaptureDevice.requestAccess(for: .audio)
        }
    }
}
