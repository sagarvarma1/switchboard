import AppKit
import ApplicationServices

/// One actionable UI element pulled from the Accessibility tree.
/// `frame` is in global AX coordinates (origin at top-left of the primary display, y grows down).
struct UIElement {
    let id: Int
    let role: String
    let subrole: String?
    let label: String
    let frame: CGRect
    let actions: [String]
    let appName: String
    let ref: AXUIElement

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    /// Compact one-line form sent to the model.
    var promptLine: String {
        let r = role.replacingOccurrences(of: "AX", with: "")
        let f = frame.integral
        let lbl = label.isEmpty ? "(no label)" : "\"\(label)\""
        return "[\(id)] \(r) \(lbl) @\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)) in \(appName)"
    }
}

enum AXScanner {
    static let interactiveRoles: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXSearchField", "AXCheckBox", "AXRadioButton",
        "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXMenuBarItem", "AXLink", "AXComboBox",
        "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXTab", "AXCell", "AXRow",
        "AXDockItem", "AXColorWell", "AXSegmentedControl",
    ]

    static let maxNodes = 4000
    static let maxElements = 300

    /// Scans the frontmost app's windows + menu bar, plus the Dock (so the model can switch apps).
    static func scan(app: NSRunningApplication) -> [UIElement] {
        var out: [UIElement] = []
        var visited = 0
        let screens = NSScreen.screens.map { axFrame(of: $0) }
        let appName = app.localizedName ?? "App"

        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 1.0)
        // Chromium/Electron only build their AX tree when asked.
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

        var roots: [AXUIElement] = []
        if let menuBar: AXUIElement = attr(appEl, kAXMenuBarAttribute) { roots.append(menuBar) }
        if let windows: [AXUIElement] = attr(appEl, kAXWindowsAttribute) { roots.append(contentsOf: windows) }

        for root in roots {
            walk(root, depth: 0, appName: appName, screens: screens, visited: &visited, out: &out)
        }

        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            let dockEl = AXUIElementCreateApplication(dock.processIdentifier)
            AXUIElementSetMessagingTimeout(dockEl, 0.5)
            walk(dockEl, depth: 0, appName: "Dock", screens: screens, visited: &visited, out: &out)
        }

        // Re-number after filtering so IDs are dense and stable within one scan.
        return out.prefix(maxElements).enumerated().map { i, e in
            UIElement(id: i, role: e.role, subrole: e.subrole, label: e.label, frame: e.frame,
                      actions: e.actions, appName: e.appName, ref: e.ref)
        }
    }

    private static func walk(_ el: AXUIElement, depth: Int, appName: String, screens: [CGRect],
                             visited: inout Int, out: inout [UIElement]) {
        guard depth < 40, visited < maxNodes, out.count < maxElements * 2 else { return }
        visited += 1

        let role: String = attr(el, kAXRoleAttribute) ?? ""
        let frame = frameOf(el)
        let onScreen = frame.map { f in f.width > 1 && f.height > 1 && screens.contains { $0.intersects(f) } } ?? false

        // Skip subtrees that are fully off-screen (closed menus, hidden tabs), except containers without frames.
        if let f = frame, f.width > 1, !onScreen, role != "AXApplication", role != "AXMenuBar" { return }

        let actions = actionNames(el)
        let enabled: Bool = attr(el, kAXEnabledAttribute) ?? true
        if onScreen, enabled, interactiveRoles.contains(role) || actions.contains(kAXPressAction as String) {
            out.append(UIElement(id: out.count, role: role, subrole: attr(el, kAXSubroleAttribute),
                                 label: label(of: el), frame: frame!, actions: actions,
                                 appName: appName, ref: el))
        }

        if let children: [AXUIElement] = attr(el, kAXChildrenAttribute) {
            for c in children {
                walk(c, depth: depth + 1, appName: appName, screens: screens, visited: &visited, out: &out)
            }
        }
    }

    /// The element under a global point (AX coords). Used to record the user's correction.
    static func element(at point: CGPoint) -> (role: String, label: String, frame: CGRect?)? {
        var ref: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &ref) == .success,
              let el = ref else { return nil }
        return (attr(el, kAXRoleAttribute) ?? "?", label(of: el), frameOf(el))
    }

    // MARK: - Helpers

    static func label(of el: AXUIElement) -> String {
        let keys = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
                    kAXPlaceholderValueAttribute, kAXHelpAttribute, kAXIdentifierAttribute]
        for k in keys {
            if let s: String = attr(el, k), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return String(s.replacingOccurrences(of: "\n", with: " ").prefix(80))
            }
        }
        // Fall back to a static-text child (common for buttons in web views).
        if let children: [AXUIElement] = attr(el, kAXChildrenAttribute) {
            for c in children.prefix(4) {
                if let s: String = attr(c, kAXValueAttribute) ?? attr(c, kAXTitleAttribute), !s.isEmpty {
                    return String(s.prefix(80))
                }
            }
        }
        return ""
    }

    static func frameOf(_ el: AXUIElement) -> CGRect? {
        guard let posVal: AXValue = attr(el, kAXPositionAttribute),
              let sizeVal: AXValue = attr(el, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(posVal, .cgPoint, &p)
        AXValueGetValue(sizeVal, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    static func actionNames(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success, let v = value else { return nil }
        return v as? T
    }

    /// An NSScreen's frame converted to global AX coordinates.
    static func axFrame(of screen: NSScreen) -> CGRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        return CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
    }
}
