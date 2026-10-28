import Carbon
import Foundation

/// Global hotkeys via Carbon's RegisterEventHotKey (no extra permission needed).
final class Hotkeys {
    static let shared = Hotkeys()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { Hotkeys.shared.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Registers a hotkey; returns an id you can pass to `unregister`.
    @discardableResult
    func register(keyCode: Int, modifiers: Int, _ handler: @escaping () -> Void) -> UInt32 {
        let id = nextID; nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4748_4354), id: id) // 'GHCT'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
        if let ref { refs[id] = ref }
        handlers[id] = handler
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }
}

enum Key {
    static let space = kVK_Space, escape = kVK_Escape, g = kVK_ANSI_G, d = kVK_ANSI_D
    static let option = optionKey
}
