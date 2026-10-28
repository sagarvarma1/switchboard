import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class SetupModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, apiKey, accessibility, screen, done

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .apiKey: "Connect Claude"
            case .accessibility: "Accessibility"
            case .screen: "Screen Recording"
            case .done: "Ready"
            }
        }
    }

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
        else if !CGPreflightScreenCaptureAccess() { step = .screen; screenRequested = true }
        else { step = .done }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        if hasAX != AXIsProcessTrusted() { withAnimation(.spring(duration: 0.35)) { hasAX.toggle() } }
        if hasScreen != CGPreflightScreenCaptureAccess() { withAnimation(.spring(duration: 0.35)) { hasScreen.toggle() } }
        if step == .accessibility && hasAX { advance(after: 0.9) }
        if step == .screen && hasScreen { advance(after: 0.9) }
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
        withAnimation(.easeInOut(duration: 0.22)) { step = n }
    }

    func back() {
        guard let p = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.22)) { step = p }
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

// MARK: - Layout

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
            Rectangle().fill(Theme.border).frame(width: 1)
            ZStack {
                Theme.canvas
                Group {
                    switch model.step {
                    case .welcome: WelcomeStep(model: model)
                    case .apiKey: KeyStep(model: model)
                    case .accessibility: AccessibilityStep(model: model)
                    case .screen: ScreenStep(model: model)
                    case .done: DoneStep(model: model)
                    }
                }
                .id(model.step)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 12)),
                                        removal: .opacity.combined(with: .offset(x: -12))))
            }
        }
        .frame(width: 800, height: 540)
        .background(Theme.canvas)
    }
}

private struct Sidebar: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppMark(size: 26)
                Text("Ghost Cursor").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            }
            .padding(.top, 52)
            .padding(.bottom, 36)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(SetupModel.Step.allCases, id: \.self) { s in
                    StepRow(step: s, current: model.step)
                    if s != SetupModel.Step.allCases.last {
                        Rectangle()
                            .fill(s.rawValue < model.step.rawValue ? Theme.accent.opacity(0.5) : Theme.border)
                            .frame(width: 1.5, height: 18)
                            .padding(.leading, 7.25)
                    }
                }
            }

            Spacer()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(Theme.text3).padding(.top, 1)
                Text("Private by design. Your key and history stay on this Mac.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(width: 236)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }
}

private struct StepRow: View {
    let step: SetupModel.Step
    let current: SetupModel.Step

    var body: some View {
        let done = step.rawValue < current.rawValue
        let active = step == current
        HStack(spacing: 12) {
            ZStack {
                if done {
                    Circle().fill(Theme.accent)
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                } else if active {
                    Circle().strokeBorder(Theme.accent, lineWidth: 1.5)
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                } else {
                    Circle().strokeBorder(Theme.border, lineWidth: 1.5)
                }
            }
            .frame(width: 16, height: 16)
            Text(step.title)
                .font(.system(size: 13, weight: active ? .medium : .regular))
                .foregroundStyle(active ? Theme.text : done ? Theme.text2 : Theme.text3)
        }
        .animation(.easeInOut(duration: 0.2), value: current)
    }
}

/// Shared scaffold for every step: eyebrow, title, body, visual, footer.
private struct StepPage<Visual: View, Actions: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var showBack = true
    var back: () -> Void = {}
    @ViewBuilder let visual: Visual
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                .foregroundStyle(Theme.accentText)
                .padding(.bottom, 10)
            Text(title)
                .font(.system(size: 26, weight: .semibold)).tracking(-0.4)
                .foregroundStyle(Theme.text)
                .padding(.bottom, 8)
            Text(subtitle)
                .font(.system(size: 14)).foregroundStyle(Theme.text2).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440, alignment: .leading)
            visual.padding(.top, 32)
            Spacer(minLength: 24)
            HStack {
                if showBack { Button("Back", action: back).buttonStyle(QuietButtonStyle()) }
                Spacer()
                actions
            }
        }
        .padding(.horizontal, 44)
        .padding(.top, 56)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        StepPage(eyebrow: "Welcome",
                 title: "Your next click, already pointed out.",
                 subtitle: "Say what you want to do. A ghost cursor shows you where to click, one step at a time. You stay in control.",
                 showBack: false) {
            HeroDemo()
        } actions: {
            Text("About a minute to set up").font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.trailing, 8)
            Button("Get started") { model.next() }
                .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
        }
    }
}

private struct KeyStep: View {
    @ObservedObject var model: SetupModel
    @FocusState private var focused: Bool

    var body: some View {
        StepPage(eyebrow: "Step 1 of 3", title: "Connect to Claude",
                 subtitle: "Ghost Cursor uses your Anthropic API key to decide each step. Usage is billed to your account.",
                 back: model.back) {
            VStack(alignment: .leading, spacing: 10) {
                Text("API key").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
                SecureField("", text: $model.keyInput, prompt: Text("sk-ant-api03-…").foregroundStyle(Theme.text3))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit { model.saveKey() }
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.canvas))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(model.keyError != nil ? Theme.danger : focused ? Theme.accent : Theme.border,
                                      lineWidth: focused ? 1.5 : 1))
                    .shadow(color: focused ? Theme.accent.opacity(0.15) : .clear, radius: 4)
                if let err = model.keyError {
                    Label(err, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.danger)
                } else {
                    Label("Stored only on this Mac, in ~/.ghostcursor", systemImage: "lock.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.text3)
                }
                Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                    HStack(spacing: 3) {
                        Text("Get a key from the Anthropic Console")
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accentText)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 420)
            .onAppear { focused = true }
        } actions: {
            Button { model.saveKey() } label: {
                if model.verifying {
                    HStack(spacing: 6) { ProgressView().controlSize(.mini).tint(.white); Text("Checking") }
                } else { Text("Continue") }
            }
            .buttonStyle(PrimaryButtonStyle(showsReturn: !model.verifying))
            .keyboardShortcut(.defaultAction)
            .disabled(model.keyInput.isEmpty || model.verifying)
        }
    }
}

private struct AccessibilityStep: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        StepPage(eyebrow: "Step 2 of 3", title: "Allow Accessibility",
                 subtitle: "This lets Ghost Cursor read the buttons on your screen and press the one you accept. It never acts without your keypress.",
                 back: model.back) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsMock(pane: "Accessibility", granted: model.hasAX)
                StatusChip(granted: model.hasAX)
            }
        } actions: {
            if model.hasAX {
                Button("Continue") { model.next() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            } else {
                Button("Open System Settings") { model.requestAccessibility() }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct ScreenStep: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        StepPage(eyebrow: "Step 3 of 3", title: "Allow Screen Recording",
                 subtitle: "Ghost Cursor looks at your screen when choosing a step. Screenshots go to Claude only while a goal is running and are never saved to disk.",
                 back: model.back) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsMock(pane: "Screen & System Audio Recording", granted: model.hasScreen)
                HStack(spacing: 12) {
                    StatusChip(granted: model.hasScreen)
                    if model.screenRequested && !model.hasScreen {
                        Text("macOS applies this after a quick relaunch.")
                            .font(.system(size: 12)).foregroundStyle(Theme.text3)
                    }
                }
            }
        } actions: {
            if model.hasScreen {
                Button("Continue") { model.next() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            } else if model.screenRequested {
                Button("Open System Settings") { model.requestScreen() }.buttonStyle(SecondaryButtonStyle())
                Button("Relaunch Ghost Cursor") { model.relaunch() }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            } else {
                Button("Open System Settings") { model.requestScreen() }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct DoneStep: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        StepPage(eyebrow: "All set", title: "You're ready.",
                 subtitle: "These work in any app. Try one now: we'll open Finder with an example goal.",
                 back: model.back) {
            VStack(spacing: 0) {
                shortcut(["⌥", "G"], "Tell Ghost Cursor what you want to do")
                Divider().overlay(Theme.border)
                shortcut(["⌥", "Space"], "Accept the step; it clicks for you")
                Divider().overlay(Theme.border)
                shortcut(["⌥", "Esc"], "Reject and click it yourself; it learns from you")
            }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
            .frame(maxWidth: 460)
        } actions: {
            Button("Try it in Finder") { model.finish() }
                .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
        }
    }

    private func shortcut(_ keys: [String], _ text: String) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) { ForEach(keys, id: \.self) { Keycap(label: $0) } }
                .frame(width: 84, alignment: .leading)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.text2)
            Spacer()
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Visuals

/// A small fake app window where the ghost glides to "Export" and offers ⌥Space, on a loop.
private struct HeroDemo: View {
    @State private var phase = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Theme.border).frame(width: 9, height: 9) }
                Spacer()
            }
            .padding(.horizontal, 12).frame(height: 30)
            Rectangle().fill(Theme.border).frame(height: 1)

            HStack(spacing: 8) {
                pill("Share"); pill("Duplicate")
                pill("Export", highlighted: phase >= 2 && phase < 4)
                    .overlay(alignment: .topLeading) {
                        ghost.offset(x: phase >= 2 ? 34 : -150, y: phase >= 2 ? 16 : 92)
                    }
                Spacer()
                RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.7)).frame(width: 56, height: 8)
            }
            .padding(.horizontal, 14).padding(.top, 14)
            .zIndex(1)

            VStack(alignment: .leading, spacing: 9) {
                ForEach([0.9, 0.75, 0.82, 0.5], id: \.self) { w in
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3).fill(Theme.border.opacity(0.6)).frame(width: g.size.width * w, height: 7)
                    }
                    .frame(height: 7)
                }
            }
            .padding(14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 480).frame(height: 176)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
        .task { await loop() }
    }

    private var ghost: some View {
        HStack(alignment: .top, spacing: 6) {
            CursorShape().fill(Theme.accent)
                .overlay(CursorShape().stroke(.white, lineWidth: 1))
                .frame(width: 14, height: 21)
                .shadow(color: Theme.accent.opacity(0.5), radius: 5)
            HStack(spacing: 5) {
                Text("Export as PNG").foregroundStyle(.white)
                Text("⌥ Space").foregroundStyle(.white.opacity(0.6))
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.82)))
            .offset(y: 14)
            .opacity(phase == 3 ? 1 : 0)
            .scaleEffect(phase == 3 ? 1 : 0.92, anchor: .topLeading)
        }
        .opacity(phase >= 1 && phase < 4 ? 1 : 0)
        .fixedSize()
    }

    private func pill(_ title: String, highlighted: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(highlighted ? Theme.accentText : Theme.text2)
            .padding(.horizontal, 10).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(highlighted ? Theme.accentSoft : Theme.canvas))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(highlighted ? Theme.accent : Theme.border, lineWidth: highlighted ? 1.5 : 1))
    }

    private func loop() async {
        while !Task.isCancelled {
            phase = 0
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.easeOut(duration: 0.3)) { phase = 1 }
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.spring(response: 0.75, dampingFraction: 0.86)) { phase = 2 }
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeOut(duration: 0.25)) { phase = 3 }
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeIn(duration: 0.35)) { phase = 4 }
            try? await Task.sleep(for: .seconds(0.6))
        }
    }
}

/// What the user will see in System Settings, with our row highlighted.
private struct SettingsMock: View {
    let pane: String
    let granted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                Text("Privacy & Security").font(.system(size: 11))
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                Text(pane).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 14).frame(height: 32)
            Rectangle().fill(Theme.border).frame(height: 1)

            VStack(spacing: 0) {
                placeholderRow(width: 74)
                Divider().overlay(Theme.border).padding(.leading, 48)
                HStack(spacing: 10) {
                    AppMark(size: 24)
                    Text("GhostCursor").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    Spacer()
                    MockToggle(on: granted)
                }
                .padding(.horizontal, 12).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(granted ? .clear : Theme.accentSoft))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(granted ? .clear : Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                Divider().overlay(Theme.border).padding(.leading, 48)
                placeholderRow(width: 58)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .frame(maxWidth: 460)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
    }

    private func placeholderRow(width: CGFloat) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.border.opacity(0.8)).frame(width: 24, height: 24)
            RoundedRectangle(cornerRadius: 3).fill(Theme.border.opacity(0.8)).frame(width: width, height: 8)
            Spacer()
            MockToggle(on: true, tint: Theme.border)
        }
        .padding(.horizontal, 12).frame(height: 38)
    }
}

private struct MockToggle: View {
    let on: Bool
    var tint: Color = Theme.accent
    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? tint : Theme.border)
            Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 1, y: 0.5).padding(2)
        }
        .frame(width: 30, height: 17)
        .animation(.spring(duration: 0.3), value: on)
    }
}

private struct StatusChip: View {
    let granted: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                if !granted {
                    Circle().fill(Theme.warning.opacity(0.35)).frame(width: 12, height: 12)
                        .scaleEffect(pulse ? 1.25 : 0.7).opacity(pulse ? 0 : 1)
                }
                Circle().fill(granted ? Theme.success : Theme.warning).frame(width: 6, height: 6)
            }
            .frame(width: 12, height: 12)
            Text(granted ? "Permission granted" : "Waiting for you to turn it on")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(granted ? Theme.success : Theme.text2)
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .fixedSize()
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

// MARK: - Window

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
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 540),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.contentView = NSHostingView(rootView: SetupView(model: model))
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Snapshots (dev only: `GhostCursor --render-setup <dir>`)

@MainActor
enum SetupSnapshots {
    static func render(to dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for step in SetupModel.Step.allCases {
                let model = SetupModel()
                model.step = step
                if step == .apiKey { model.keyInput = "sk-ant-api03-xxxxxxxx" }
                let view = NSHostingView(rootView: SetupView(model: model))
                view.frame = CGRect(x: 0, y: 0, width: 800, height: 540)
                let w = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                w.appearance = NSAppearance(named: appearance)
                w.contentView = view
                view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(step == .welcome ? 2.6 : 0.3))
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: url.appendingPathComponent("\(step.rawValue)-\(step)-\(name).png"))
            }
        }
    }
}
