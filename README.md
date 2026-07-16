# Seer

On-device inline autocomplete for any macOS text field. Seer reads the text you're typing
(locally, via the Accessibility APIs), predicts the next few words with a local language
model (Qwen 2.5 1.5B via llama.cpp — no network, nothing leaves your Mac), and shows the
suggestion as ghost text you accept with Tab.

- Works in (almost) any app's text field
- Fully offline — the model runs on-device (Metal)
- Tab accepts the next word, ⇧Tab the whole line, Esc dismisses
- Menu-bar controls: global on/off, pause-for-current-app; panic hotkey ⌃⌥⌘.

Requires an Apple Silicon Mac on macOS 14+.

## Install

```bash
brew tap thrtn70/seer
brew install --cask seer
```

First launch asks for **Accessibility** and **Input Monitoring** — Seer needs both to read
the focused text field and to detect Tab/Esc. Grant them in the window that appears; it
continues automatically once both are on.

Seer is un-notarized (personal project, self-signed). The cask clears the quarantine flag
on install; if Gatekeeper still complains, right-click Seer.app → Open → Open.

## Build from source

```bash
scripts/fetch-llama.sh    # llama.cpp xcframework (pinned tag)
scripts/fetch-model.sh    # Qwen 2.5 1.5B instruct GGUF (~1 GB)
swift test                # unit tests
scripts/build-app.sh      # -> build/Seer.app (details in docs/packaging.md)
```

`swift run SeerAgent` also works for development (the model is resolved from `vendor/`).
