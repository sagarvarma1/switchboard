import AppKit

/// Drives the loop: see → predict → show → accept/reject → repeat.
@MainActor
final class Session {
    let id = UUID().uuidString.prefix(8).lowercased()
    let goal: String
    private let overlay: Overlay
    private let predictor = Predictor()
    private var history: [String] = []
    private var step = 0
    private var current: (pred: Prediction, el: UIElement, app: String, latency: Int, count: Int)?
    private var hotkeyIDs: [UInt32] = []
    private var clickMonitor: Any?
    private var task: Task<Void, Never>?
    private(set) var active = true
    var onEnd: (() -> Void)?

    init(goal: String, overlay: Overlay) {
        self.goal = goal
        self.overlay = overlay
    }

    func start() { next(after: 0) }

    func stop(_ message: String? = nil) {
        active = false
        task?.cancel()
        disarm()
        stopWatchingForCorrection()
        if let message {
            overlay.showMessage(message)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [overlay] in
                if overlay.mode == .message { overlay.hide() }
            }
        } else {
            overlay.hide()
        }
        onEnd?()
    }

    // MARK: - Loop

    private func next(after delay: TimeInterval) {
        guard active else { return }
        step += 1
        task = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            await self?.predictStep()
        }
    }

    private func predictStep() async {
        guard active else { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return stop("Click into the app you want help with, then start again.")
        }
        overlay.showThinking()

        let t0 = Date()
        let elements = await Task.detached { AXScanner.scan(app: app) }.value
        guard !elements.isEmpty else { return stop("No accessible elements found in \(app.localizedName ?? "this app").") }

        do {
            let shot = try await ScreenCapture.captureAnnotated(elements: elements)
            let pred = try await predictor.predict(goal: goal, history: history, elements: elements, screenshot: shot.png)
            guard active, !Task.isCancelled else { return }
            let latency = Int(Date().timeIntervalSince(t0) * 1000)

            if pred.action == "done" {
                log(pred: pred, el: nil, app: app.localizedName ?? "?", latency: latency, count: elements.count, outcome: "done")
                return stop("✓ Done: \(pred.reason)")
            }
            guard let el = elements.first(where: { $0.id == pred.element_id }) else {
                return stop("Model picked an unknown element (\(pred.element_id)).")
            }
            current = (pred, el, app.localizedName ?? "?", latency, elements.count)
            let verb = pred.action == "type" ? "Type “\(pred.text)”: " : ""
            overlay.point(to: el.frame, label: verb + pred.reason, confidence: pred.confidence)
            arm()
        } catch {
            stop("⚠︎ \(error.localizedDescription)")
        }
    }

    // MARK: - Accept / reject

    private func arm() {
        disarm()
        hotkeyIDs = [
            Hotkeys.shared.register(keyCode: Key.space, modifiers: Key.option) { [weak self] in self?.accept() },
            Hotkeys.shared.register(keyCode: Key.escape, modifiers: Key.option) { [weak self] in self?.reject() },
        ]
    }

    private func disarm() {
        hotkeyIDs.forEach { Hotkeys.shared.unregister($0) }
        hotkeyIDs = []
    }

    private func accept() {
        guard let c = current else { return }
        disarm()
        current = nil
        log(pred: c.pred, el: c.el, app: c.app, latency: c.latency, count: c.count, outcome: "accepted")
        overlay.showThinking(near: c.el.center, "")
        if c.pred.action == "type" {
            Actuator.type(c.pred.text, into: c.el)
            history.append("Typed \"\(c.pred.text)\" into \(c.el.role) \"\(c.el.label)\" (accepted)")
        } else {
            Actuator.click(c.el)
            history.append("Clicked \(c.el.role) \"\(c.el.label)\" in \(c.app) (accepted)")
        }
        next(after: 0.7) // let the UI settle
    }

    private func reject() {
        guard let c = current else { return }
        disarm()
        current = nil
        overlay.showMessage("Rejected. Click the right thing yourself — I'll learn from it.")
        var event = makeEvent(pred: c.pred, el: c.el, app: c.app, latency: c.latency, count: c.count, outcome: "rejected")
        history.append("Suggested \(c.el.role) \"\(c.el.label)\" but the user REJECTED it")

        // Wait for the user's own click and record it as the correction.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stopWatchingForCorrection()
                let m = NSEvent.mouseLocation
                let primaryH = NSScreen.screens.first?.frame.height ?? 0
                let hit = AXScanner.element(at: CGPoint(x: m.x, y: primaryH - m.y))
                event.correctionRole = hit?.role
                event.correctionLabel = hit?.label
                EventLog.append(event)
                self.history.append("User clicked \(hit?.role ?? "something") \"\(hit?.label ?? "")\" themselves instead")
                self.next(after: 0.8)
            }
        }
    }

    private func stopWatchingForCorrection() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
    }

    // MARK: - Logging

    private func makeEvent(pred: Prediction, el: UIElement?, app: String, latency: Int, count: Int, outcome: String) -> EvalEvent {
        EvalEvent(session: String(id), goal: goal, step: step, app: app, model: Predictor.model,
                  action: pred.action, elementRole: el?.role ?? "", elementLabel: el?.label ?? "",
                  confidence: pred.confidence, latencyMs: latency, elementCount: count, outcome: outcome)
    }

    private func log(pred: Prediction, el: UIElement?, app: String, latency: Int, count: Int, outcome: String) {
        EventLog.append(makeEvent(pred: pred, el: el, app: app, latency: latency, count: count, outcome: outcome))
    }
}
