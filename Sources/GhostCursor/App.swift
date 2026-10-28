import AppKit
import ApplicationServices

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        if let i = CommandLine.arguments.firstIndex(of: "--render-setup"), i + 1 < CommandLine.arguments.count {
            app.setActivationPolicy(.accessory)
            MainActor.assumeIsolated { SetupSnapshots.render(to: CommandLine.arguments[i + 1]) }
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }

    private var statusItem: NSStatusItem!
    private var overlay: Overlay!
    private var goalPanel: GoalPanel!
    private var session: Session?
    private var debugOn = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = Overlay()
        goalPanel = GoalPanel { [weak self] goal in self?.startSession(goal) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "Ghost Cursor")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        rebuildMenu()

        Hotkeys.shared.register(keyCode: Key.g, modifiers: Key.option) { [weak self] in self?.showGoal() }
        Hotkeys.shared.register(keyCode: Key.d, modifiers: Key.option) { [weak self] in self?.toggleDebug() }

        if !SetupModel.isComplete || !UserDefaults.standard.bool(forKey: "onboarded") { showSetup() }
    }

    // MARK: - Setup

    private let setupWindow = SetupWindow()
    private var hasAX: Bool { AXIsProcessTrusted() }
    private var hasScreen: Bool { CGPreflightScreenCaptureAccess() }

    @objc private func showSetup() {
        setupWindow.show { [weak self] in
            UserDefaults.standard.set(true, forKey: "onboarded")
            self?.rebuildMenu()
            self?.tryInFinder()
        }
    }

    /// First run: bring Finder forward and open the goal box with an example ready to go.
    private func tryInFinder() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.goalPanel.present(prefill: "open the Downloads folder")
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        if let s = session, s.active {
            menu.addItem(withTitle: "Goal: \(s.goal.prefix(40))", action: nil, keyEquivalent: "")
            menu.addItem(item("Stop", #selector(stopSession)))
        } else {
            menu.addItem(item("New Goal…  (⌥G)", #selector(showGoal)))
        }
        menu.addItem(item(debugOn ? "Hide Element Boxes  (⌥D)" : "Show Element Boxes  (⌥D)", #selector(toggleDebug)))
        menu.addItem(.separator())
        if !SetupModel.isComplete { menu.addItem(item("⚠︎ Finish Setup…", #selector(showSetup))) }
        else { menu.addItem(item("Setup…", #selector(showSetup))) }
        menu.addItem(item("Reveal Eval Log", #selector(revealLog)))
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit)))
        menu.delegate = self
        statusItem.menu = menu
    }

    private func item(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    // MARK: - Actions

    @objc private func showGoal() {
        guard session?.active != true else { return }
        goalPanel.present()
    }

    private func startSession(_ goal: String) {
        session?.stop()
        let s = Session(goal: goal, overlay: overlay)
        s.onEnd = { [weak self] in self?.rebuildMenu() }
        session = s
        rebuildMenu()
        s.start()
    }

    @objc private func stopSession() { session?.stop() }

    @objc private func toggleDebug() {
        debugOn.toggle()
        rebuildMenu()
        guard debugOn else { overlay.debugBoxes = []; return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        Task {
            let els = await Task.detached { AXScanner.scan(app: app) }.value
            if self.debugOn { self.overlay.debugBoxes = els }
        }
    }

    @objc private func revealLog() {
        if !FileManager.default.fileExists(atPath: EventLog.url.path) {
            FileManager.default.createFile(atPath: EventLog.url.path, contents: nil)
        }
        NSWorkspace.shared.activateFileViewerSelecting([EventLog.url])
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }
}
