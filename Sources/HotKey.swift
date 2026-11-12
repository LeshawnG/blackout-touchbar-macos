// A global keyboard shortcut using Carbon's RegisterEventHotKey.
// Unlike event taps or global key monitors, this needs no Accessibility or
// Input Monitoring permission: macOS only tells us when this exact combo is pressed.

import Carbon

final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?

    /// Returns nil if the combo is already taken or Carbon refuses it.
    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping () -> Void) {
        if !HotKey.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let id = hotKeyID.id
                DispatchQueue.main.async { HotKey.handlers[id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            guard status == noErr else { return nil }
            HotKey.handlerInstalled = true
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x544B_424F) /* 'TKBO' */, id: id)
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else {
            return nil
        }
        HotKey.handlers[id] = handler
    }

    deinit {
        if let ref = ref { UnregisterEventHotKey(ref) }
    }
}
