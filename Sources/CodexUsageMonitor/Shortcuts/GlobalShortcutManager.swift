import Carbon.HIToolbox
import Foundation
import OSLog

final class GlobalShortcutManager {
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private(set) var isRegistered = false
    private var selectedKey = ShortcutKey.c

    deinit {
        unregister()
    }

    func setEnabled(_ enabled: Bool, key: ShortcutKey) {
        if key != selectedKey {
            unregister()
            selectedKey = key
        }
        enabled ? register() : unregister()
    }

    private func register() {
        guard !isRegistered else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalShortcutManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                manager.handleShortcut()
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandlerReference
        )
        guard handlerStatus == noErr else { return }

        let identifier = EventHotKeyID(signature: 0x4344_5855, id: 1) // CDXU
        let modifiers = UInt32(controlKey | optionKey)
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        isRegistered = registrationStatus == noErr

        if !isRegistered, let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    private var keyCode: UInt32 {
        switch selectedKey {
        case .c: return UInt32(kVK_ANSI_C)
        case .m: return UInt32(kVK_ANSI_M)
        case .u: return UInt32(kVK_ANSI_U)
        }
    }

    private func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
        isRegistered = false
    }

    private func handleShortcut() {
        Logger(subsystem: "com.kimjaeyun.codexusagemonitor", category: "Lifecycle")
            .notice("Global shortcut received")
        DispatchQueue.main.async {
            AppVisibilityController.shared.showUsage()
        }
    }
}
