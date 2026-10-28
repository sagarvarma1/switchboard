import AppKit

/// Click-through, transparent windows (one per screen) that draw the ghost cursor.
/// All state is in global AX coordinates; each screen's view translates to its own space.
@MainActor
final class Overlay {
    enum Mode { case hidden, thinking, pointing, message }

    private var windows: [NSWindow] = []
    private var views: [OverlayView] = []
    private var animTimer: Timer?

    var mode: Mode = .hidden { didSet { redraw() } }
    var target: CGRect?
    var label = ""
    var confidence: Double = 1
    var debugBoxes: [UIElement] = [] { didSet { redraw() } }
    private(set) var ghostPos = CGPoint(x: 200, y: 200)

    init() {
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows = []; views = []
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.sharingType = .none
            let v = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
            v.overlay = self
            v.screenAX = AXScanner.axFrame(of: screen)
            w.contentView = v
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w); views.append(v)
        }
    }

    func redraw() { views.forEach { $0.needsDisplay = true } }

    /// Glide the ghost from its current position to the target's center.
    func point(to rect: CGRect, label: String, confidence: Double) {
        self.target = rect
        self.label = label
        self.confidence = confidence
        mode = .pointing
        let start = ghostPos
        let end = CGPoint(x: rect.midX, y: rect.midY)
        let t0 = CACurrentMediaTime(), dur = 0.45
        animTimer?.invalidate()
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return t.invalidate() }
                let p = min(1, (CACurrentMediaTime() - t0) / dur)
                let e = 1 - pow(1 - p, 3) // ease-out cubic
                self.ghostPos = CGPoint(x: start.x + (end.x - start.x) * e, y: start.y + (end.y - start.y) * e)
                self.redraw()
                if p >= 1 { t.invalidate() }
            }
        }
    }

    func showThinking(near point: CGPoint? = nil, _ text: String = "Thinking…") {
        if let point { ghostPos = point }
        target = nil
        label = text
        mode = .thinking
    }

    func showMessage(_ text: String) {
        target = nil
        label = text
        mode = .message
    }

    func hide() {
        mode = .hidden
        target = nil
    }
}

final class OverlayView: NSView {
    weak var overlay: Overlay?
    var screenAX: CGRect = .zero

    override var isFlipped: Bool { true }

    private func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - screenAX.minX, y: p.y - screenAX.minY) }
    private func local(_ r: CGRect) -> CGRect { CGRect(origin: local(r.origin), size: r.size) }

    override func draw(_ dirtyRect: NSRect) {
        guard let o = overlay else { return }

        // Debug: outline everything the scanner found.
        for el in o.debugBoxes where screenAX.intersects(el.frame) {
            let r = local(el.frame)
            NSColor.systemPink.withAlphaComponent(0.7).setStroke()
            NSBezierPath(rect: r).stroke()
            NSString(string: "\(el.id)").draw(at: CGPoint(x: r.minX + 1, y: r.minY),
                                              withAttributes: [.font: NSFont.systemFont(ofSize: 9),
                                                               .foregroundColor: NSColor.systemPink])
        }

        guard o.mode != .hidden else { return }
        // Solid when sure, faint when guessing.
        let alpha = CGFloat(0.35 + 0.65 * max(0, min(1, o.confidence)))
        let tint = Theme.nsAccent

        if o.mode == .pointing, let t = o.target, screenAX.intersects(t) {
            let r = local(t).insetBy(dx: -4, dy: -4)
            let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            tint.withAlphaComponent(0.12 * alpha).setFill(); path.fill()
            tint.withAlphaComponent(alpha).setStroke(); path.lineWidth = 2; path.stroke()
        }

        let p = local(o.ghostPos)
        let ghostVisible = bounds.insetBy(dx: -40, dy: -40).contains(p)
        if ghostVisible && o.mode != .message { drawArrow(at: p, color: tint.withAlphaComponent(alpha)) }

        // Label bubble: next to the ghost, or centered at the top for messages.
        guard !o.label.isEmpty else { return }
        let showBubbleHere = o.mode == .message ? screenAX.contains(mouseAX()) : ghostVisible
        guard showBubbleHere else { return }

        var text = o.label
        if o.mode == .pointing { text += "   \(Int(o.confidence * 100))%   ⌥Space accept · ⌥Esc reject" }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                    .foregroundColor: NSColor.white]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        var origin = o.mode == .message ? CGPoint(x: bounds.midX - size.width / 2, y: 60) : CGPoint(x: p.x + 22, y: p.y + 22)
        origin.x = min(max(8, origin.x), bounds.width - size.width - 20)
        origin.y = min(max(8, origin.y), bounds.height - size.height - 16)
        let bubble = CGRect(x: origin.x, y: origin.y, width: size.width + 16, height: size.height + 10)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 8, yRadius: 8).fill()
        s.draw(at: CGPoint(x: bubble.minX + 8, y: bubble.minY + 5))
    }

    private func mouseAX() -> CGPoint {
        let m = NSEvent.mouseLocation
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: m.x, y: primaryH - m.y)
    }

    private func drawArrow(at tip: CGPoint, color: NSColor) {
        let path = NSBezierPath()
        let pts: [CGPoint] = [(0, 0), (0, 22), (6, 17), (10, 26), (14, 24), (10, 15), (17, 15)]
            .map { CGPoint(x: tip.x + $0.0, y: tip.y + $0.1) }
        path.move(to: pts[0]); pts.dropFirst().forEach { path.line(to: $0) }; path.close()
        let shadow = NSShadow(); shadow.shadowBlurRadius = 6; shadow.shadowColor = color
        NSGraphicsContext.saveGraphicsState(); shadow.set()
        color.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.9).setStroke(); path.lineWidth = 1.2; path.stroke()
    }
}
