import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class SetupModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, apiKey, accessibility, screen, done }

    @Published var step: Step = .welcome
    @Published var keyInput = ""
    @Published var keyError: String?
    @Published var verifying = false
    @Published var hasAX = AXIsProcessTrusted()
    @Published var hasScreen = CGPreflightScreenCaptureAccess()
    @Published var screenRequested = false
    var onFinish: (() -> Void)?
    private var timer: Timer?

    static var isComplete: Bool {
        APIKey.load() != nil && AXIsProcessTrusted() && CGPreflightScreenCaptureAccess()
    }

    init() {
        keyInput = APIKey.load() ?? ""
        // Resume where we left off (e.g. after the Screen Recording relaunch).
        if APIKey.load() == nil { step = .welcome }
        else if !AXIsProcessTrusted() { step = .accessibility }
        else if !CGPreflightScreenCaptureAccess() { step = .screen }
        else { step = .done }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        hasAX = AXIsProcessTrusted()
        hasScreen = CGPreflightScreenCaptureAccess()
        if step == .accessibility && hasAX { advance(after: 0.7) }
        if step == .screen && hasScreen { advance(after: 0.7) }
    }

    private var pendingAdvance = false
    private func advance(after delay: Double) {
        guard !pendingAdvance else { return }
        pendingAdvance = true
        let from = step
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.pendingAdvance = false
            if self.step == from { self.next() }
        }
    }

    func next() {
        guard let n = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { step = n }
    }

    func back() {
        guard let p = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { step = p }
    }

    func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-ant-") else {
            keyError = "Anthropic keys start with “sk-ant-”."
            return
        }
        verifying = true
        keyError = nil
        Task {
            let problem = await APIKey.verify(key)
            verifying = false
            if let problem { keyError = problem; return }
            do { try APIKey.save(key); next() } catch { keyError = error.localizedDescription }
        }
    }

    func requestAccessibility() {
        // Adds Ghost Cursor to the list in Settings, then opens the pane so it's one toggle away.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func requestScreen() {
        screenRequested = true
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    /// macOS only applies Screen Recording after a restart of the app.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    func finish() {
        timer?.invalidate()
        onFinish?()
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(SetupModel.Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s.rawValue <= model.step.rawValue ? Color.purple : Color.secondary.opacity(0.25))
                        .frame(width: s == model.step ? 22 : 8, height: 8)
                }
            }
            .padding(.top, 22)

            Group {
                switch model.step {
                case .welcome: welcome
                case .apiKey: apiKey
                case .accessibility: accessibility
                case .screen: screen
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .frame(width: 560, height: 440)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 16) {
            Text("👻").font(.system(size: 64))
            Text("Welcome to Ghost Cursor").font(.largeTitle.bold())
            Text("Tell it what you want to do. A ghost cursor shows you the next click, and one key accepts or rejects it.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Setup takes about a minute: an API key and two permissions.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Get Started") { model.next() }
                .buttonStyle(.borderedProminent).tint(.purple).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
    }

    private var apiKey: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("key.fill", "Connect to Claude",
                       "Ghost Cursor uses your Anthropic API key. It's stored only on this Mac.")
            SecureField("sk-ant-…", text: $model.keyInput)
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                .onSubmit { model.saveKey() }
            if let err = model.keyError {
                Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
            }
            Link("Don't have one? Create a key at console.anthropic.com →",
                 destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                .font(.callout)
            Spacer()
            footer {
                Button {
                    model.saveKey()
                } label: {
                    if model.verifying { ProgressView().controlSize(.small).frame(width: 90) }
                    else { Text("Verify & Continue").frame(width: 130) }
                }
                .disabled(model.keyInput.isEmpty || model.verifying)
            }
        }
        .padding(.vertical, 24)
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("hand.point.up.left.fill", "Allow Accessibility",
                       "Lets Ghost Cursor see the buttons in your apps and click them when you accept.")
            instructions(["Click **Open Settings**",
                          "Turn on the switch next to **GhostCursor**",
                          "Come back here; it continues on its own"])
            status(model.hasAX, waiting: "Waiting for permission…", granted: "Accessibility granted")
            Spacer()
            footer {
                if model.hasAX {
                    Button("Continue") { model.next() }
                } else {
                    Button("Open Settings") { model.requestAccessibility() }
                }
            }
        }
        .padding(.vertical, 24)
    }

    private var screen: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("rectangle.dashed.badge.record", "Allow Screen Recording",
                       "Lets Ghost Cursor look at your screen when it's choosing the next step. Nothing is saved.")
            instructions(["Click **Open Settings**",
                          "Turn on the switch next to **GhostCursor**",
                          "Click **Relaunch** below (macOS needs a restart for this one)"])
            status(model.hasScreen, waiting: "Waiting for permission…", granted: "Screen Recording granted")
            Spacer()
            footer {
                if model.hasScreen {
                    Button("Continue") { model.next() }
                } else if model.screenRequested {
                    HStack {
                        Button("Open Settings") { model.requestScreen() }.buttonStyle(.bordered).tint(nil)
                        Button("Relaunch") { model.relaunch() }
                    }
                } else {
                    Button("Open Settings") { model.requestScreen() }
                }
            }
        }
        .padding(.vertical, 24)
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(.green)
            Text("You're all set").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 8) {
                keyRow("⌥ G", "Tell the ghost what you want to do")
                keyRow("⌥ Space", "Accept: it clicks for you")
                keyRow("⌥ Esc", "Reject: you click the right thing")
                keyRow("👻", "Menu bar icon: settings, stop, eval log")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
            Button("Try It in Finder") { model.finish() }
                .buttonStyle(.borderedProminent).tint(.purple).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
    }

    // MARK: - Pieces

    private func stepHeader(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.purple)
            Text(title).font(.title.bold())
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func instructions(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(Circle().fill(Color.purple))
                    Text(.init(line))
                }
            }
        }
    }

    private func status(_ ok: Bool, waiting: String, granted: String) -> some View {
        HStack(spacing: 8) {
            if ok { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            else { ProgressView().controlSize(.small) }
            Text(ok ? granted : waiting).foregroundStyle(ok ? .primary : .secondary)
        }
        .font(.callout)
    }

    private func keyRow(_ key: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(key).font(.system(.body, design: .rounded).bold()).frame(width: 80, alignment: .leading)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func footer<C: View>(@ViewBuilder _ primary: () -> C) -> some View {
        HStack {
            Button("Back") { model.back() }.buttonStyle(.borderless)
            Spacer()
            primary()
                .buttonStyle(.borderedProminent).tint(.purple).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// Hosts the wizard in a regular window.
@MainActor
final class SetupWindow {
    private var window: NSWindow?

    func show(onFinish: @escaping () -> Void) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let model = SetupModel()
        model.onFinish = { [weak self] in
            self?.window?.close()
            self?.window = nil
            onFinish()
        }
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 440),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SetupView(model: model))
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
