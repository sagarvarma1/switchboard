import AppKit
import ApplicationServices

enum Actuator {
    static func click(_ el: UIElement) {
        // Prefer the semantic action; it works even if the element is partly covered.
        if el.actions.contains(kAXPressAction as String),
           AXUIElementPerformAction(el.ref, kAXPressAction as CFString) == .success {
            return
        }
        mouseClick(at: el.center)
    }

    static func type(_ text: String, into el: UIElement) {
        AXUIElementSetAttributeValue(el.ref, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        mouseClick(at: el.center)
        usleep(120_000)
        typeString(text)
    }

    static func mouseClick(at p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            usleep(20_000)
        }
    }

    static func typeString(_ s: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for line in s.components(separatedBy: "\n").enumerated() {
            if line.offset > 0 { pressKey(36) } // Return
            for ch in line.element.utf16 {
                var c = ch
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                    e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
                    e?.post(tap: .cghidEventTap)
                }
                usleep(8_000)
            }
        }
    }

    static func pressKey(_ code: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    }
}
