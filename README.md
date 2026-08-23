# parrot

A minimal macOS dictation daemon. CLI-launched, push-to-talk, on-device transcription, text inserted at the cursor.

```sh
$ parrot
listening on backslash hold · model: parakeet-tdt-0.6b-v2 · ^C to quit
```

That's it. Hold Backslash, speak, release. Text appears at the cursor in whatever app is focused. A small pill at the bottom of the screen shows when the mic is hot.

## Install

```sh
curl -fsSL https://digimata.github.io/parrot/install.sh | sh
parrot setup
parrot install --launch-at-login   # optional
```

**Requires:** macOS 14+ on Apple Silicon (M1 or newer). Transcription runs on the Apple Neural Engine via CoreML — so the installer refuses to run on Intel.

The installer drops the binary in `/usr/local/bin/parrot`. Builds are unsigned for now, so the installer strips the quarantine xattr — once you've inspected the script you'll see exactly what it does.

## Stack

- **Swift** — single SPM executable target
- **FluidAudio**: Parakeet inference via CoreML, ANE-accelerated
- **WhisperKit**: optional Whisper inference via CoreML, ANE-accelerated
- **AVAudioEngine** — mic capture
- **CGEventTap** — global hotkey
- **CGEvent** — text injection at cursor
- **NSWindow** (borderless, click-through) — recording-indicator pill at bottom of screen

No menubar, no dock icon, no app bundle, no settings window, no launch-at-login. If you want it always running, run it under `launchd` yourself or leave a terminal tab open.

## Usage 

```sh
parrot                                 # run with defaults (Backslash hold, Parakeet v2)
parrot --model whisper-base.en         # retain Whisper Base as a fallback
parrot --model whisper-large-v3-turbo  # bigger, multilingual, slower first-run
parrot --hotkey backslash           # use the unmodified \ key; Shift-\ still types |
parrot --input-device automatic     # avoid Bluetooth call mode when possible
parrot --input-device system        # explicitly use the system-default microphone
parrot --input-device built-in      # always use the Mac's built-in microphone
parrot --no-overlay                 # disable bottom-of-screen pill
parrot models list                  # list available models
parrot models download <id>         # pre-download a model
parrot doctor                       # check permissions + Fn key setting
parrot install --launch-at-login --hotkey backslash --model parakeet-tdt-0.6b-v2 --input-device built-in
parrot install --uninstall          # remove the LaunchAgent
```

For launch-at-login, persist the choice in the LaunchAgent with
`parrot install --launch-at-login --hotkey backslash`. Parrot suppresses the
unmodified `\` while it is the push-to-talk key, but modified shortcuts and
Shift-`\` continue to work normally.

By default, `automatic` follows the system microphone unless it is Bluetooth.
When a Bluetooth headset is the default input, Parrot instead opens the Mac's
built-in microphone without changing the system-wide input setting. This avoids
headset call-mode transitions and their "call ended" announcements. Pass
`--input-device system` if you intentionally want to dictate through the
headset microphone.

## Status

M0 complete (skeleton builds, daemon runs, SIGINT exits cleanly). See [docs/architecture.md](docs/architecture.md) for design and [.plan/plan.md](.plan/plan.md) for milestones.

## Build

```sh
swift build
.build/debug/parrot --help
```
