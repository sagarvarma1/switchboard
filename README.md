# Ghost Cursor

Tab-to-complete for your whole computer. A translucent ghost cursor points at the next thing to click; you accept or reject with one key, and every keypress is logged as an eval.

## Setup (one line)

```sh
git clone https://github.com/sagarvarma1/switchboard.git && cd switchboard && ./setup.sh
```

This builds the app, installs it to `~/Applications`, and opens a setup wizard for your Anthropic API key and the Accessibility and Screen Recording permissions. Requires macOS 14+ and Xcode or the Command Line Tools (the script offers to install them).

To change things later, use the menu bar icon → **Setup…**. Run `./setup.sh` again after pulling new code.

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
