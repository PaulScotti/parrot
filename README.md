# parrot

Paul Scotti's fork of [digimata/parrot](https://github.com/digimata/parrot), a
minimal, fully local macOS dictation daemon. Hold a key, speak, release, and the
transcript appears at the cursor in any app.

This fork is optimized for Backslash dictation on Apple Silicon Macs:

- Backslash is the default push-to-talk key.
- Hold Backslash for ordinary push-to-talk dictation.
- Double-tap Backslash for hands-free dictation, then tap once to stop.
- NVIDIA Parakeet TDT 0.6B v2 is the default model, using FluidAudio and Core ML.
- Bluetooth microphones are avoided automatically when a built-in Mac microphone
  is available, preventing headset call-mode transitions and "call ended" alerts.
- Shift-Backslash and modified shortcuts continue to work normally.
- A release-state fallback prevents a missed key-up from leaving recording active.

## Requirements

- macOS 14 or later
- Apple Silicon, M1 or newer
- Internet access for the first model download, approximately 452 MB
- Xcode Command Line Tools only if building from source

## Install the prebuilt release

```sh
curl -fsSL https://raw.githubusercontent.com/PaulScotti/parrot/main/scripts/install.sh | sh
parrot setup
parrot install --launch-at-login \
  --hotkey backslash \
  --model parakeet-tdt-0.6b-v2 \
  --input-device automatic
```

The installer places the binary at `/usr/local/bin/parrot`. The launch agent
starts Parrot at login and keeps it running in the background.

On first setup, grant `parrot` Microphone and Accessibility access in System
Settings. If macOS retains an obsolete Accessibility row after an update,
remove that row and add `/usr/local/bin/parrot` again.

## Build from source

Install Apple's command-line developer tools if `swift --version` is not
available:

```sh
xcode-select --install
```

Then clone, build, and install:

```sh
git clone https://github.com/PaulScotti/parrot.git
cd parrot
swift build -c release
sudo mkdir -p /usr/local/bin
sudo install -m 755 .build/release/parrot /usr/local/bin/parrot
parrot setup
parrot install --launch-at-login \
  --hotkey backslash \
  --model parakeet-tdt-0.6b-v2 \
  --input-device automatic
```

## How to use

1. Click into any text field.
2. Either hold Backslash while speaking and release it, or double-tap Backslash
   to start hands-free dictation.
3. When hands-free dictation is active, tap Backslash once to stop.
4. Parrot transcribes locally and inserts the text at the cursor.

The menu-bar item and recording pill show whether Parrot is recording or
transcribing.

## Useful commands

```sh
parrot                                  # run in the foreground
parrot setup                            # configure permissions
parrot doctor                           # check permissions and hotkey setup
parrot models list                      # list available models
parrot models download parakeet-tdt-0.6b-v2
parrot --input-device system            # intentionally use the default mic
parrot --input-device built-in          # always use the Mac microphone
parrot install --uninstall              # remove the launch agent
```

`--input-device automatic` follows the system input unless it is Bluetooth. If
the default input is Bluetooth and the Mac has a built-in microphone, Parrot
uses the built-in microphone only for its own process. The system-wide input
and the headset output remain unchanged.

## Stack

- Swift and Swift Package Manager
- FluidAudio with Parakeet TDT 0.6B v2 through Core ML
- WhisperKit as an optional fallback
- AVAudioEngine for microphone capture
- CGEventTap for the global hotkey
- CGEvent for text insertion

See [docs/architecture.md](docs/architecture.md) for implementation details.
The upstream project and this fork are distributed under the [MIT License](LICENSE).
