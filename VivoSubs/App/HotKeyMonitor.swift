import AppKit
import Carbon
import Foundation

final class HotKeyMonitor: @unchecked Sendable {
    var onToggleOverlay: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x5649564F // 'VIVO'
    private static let overlayHotKeyID: UInt32 = 1

    func register() {
        unregister()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.overlayHotKeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_H),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr else { return }
        hotKeyRef = ref

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if installed != noErr {
            unregister()
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        unregister()
    }

    fileprivate func handle(event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == Self.signature else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onToggleOverlay?()
        }
    }
}

private func hotKeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    monitor.handle(event: event)
    return noErr
}
