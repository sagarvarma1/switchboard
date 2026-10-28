import AppKit

/// Spotlight-style floating box for typing a goal. Returns focus to the previous app on submit.
@MainActor
final class GoalPanel: NSObject, NSTextFieldDelegate {
    private let panel: KeyPanel
    private let field = NSTextField()
    private var previousApp: NSRunningApplication?
    private let onSubmit: (String) -> Void

    init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
        panel = KeyPanel(contentRect: CGRect(x: 0, y: 0, width: 620, height: 56),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let bg = NSVisualEffectView(frame: panel.contentView!.bounds)
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        bg.autoresizingMask = [.width, .height]
        panel.contentView = bg

        field.frame = CGRect(x: 18, y: 14, width: 584, height: 28)
        field.font = .systemFont(ofSize: 20)
        field.placeholderString = "👻  What do you want to do?  (Esc to cancel)"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        bg.addSubview(field)
    }

    func present(prefill: String = "") {
        previousApp = NSWorkspace.shared.frontmostApplication
        field.stringValue = prefill
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - f.height * 0.28))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: prefill.utf16.count, length: 0)
    }

    private func dismiss() {
        panel.orderOut(nil)
        previousApp?.activate()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            let goal = field.stringValue.trimmingCharacters(in: .whitespaces)
            dismiss()
            if !goal.isEmpty {
                // Give the previous app a moment to come back to the front before scanning it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.onSubmit(goal) }
            }
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        return false
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
