# Ghost Cursor

Tab-to-complete for your whole computer. A translucent ghost cursor points at the next thing to click; you accept or reject with one key, and every keypress is logged as an eval.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/sagarvarma1/switchboard/main/install.sh | sh
```

Or download **GhostCursor.dmg** from the [latest release](https://github.com/sagarvarma1/switchboard/releases/latest). Requires macOS 14+ (Apple Silicon or Intel) and an Anthropic API key. The app opens a setup wizard on first launch.

### Build from source

```sh
git clone https://github.com/sagarvarma1/switchboard.git && cd switchboard && ./setup.sh
```

### Releasing

```sh
./scripts/release.sh 0.2    # universal build → DMG + zip → GitHub Release (notarized if a Developer ID is set up)
```

The website lives in `docs/` and is served by GitHub Pages.

## Keys

| Key | Does |
|---|---|
| ⌥G | Type a goal |
| ⌥Space | Accept: Ghost Cursor clicks or types for you |
| ⌥Esc | Reject: click the right thing yourself, and it gets recorded as a correction |
| ⌥D | Toggle debug boxes around every element the AX scanner found |

Eval log: `~/Library/Application Support/GhostCursor/events.jsonl`

## Layout

- `AXScanner`: walks the Accessibility tree (frontmost app + Dock) and collects interactive elements
- `ScreenCapture`: takes a ScreenCaptureKit screenshot with numbered set-of-marks boxes drawn on it
- `Predictor`: calls the Claude Messages API with structured JSON output and gets back an element id, action, confidence and reason
- `Overlay`: draws the ghost in a click-through window
- `Session`: runs the see → predict → show → accept/reject loop
- `Actuator`: clicks and types through AXPress and CGEvent
- `EventLog`: writes JSONL eval events
