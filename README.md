# parrot

Paul Scotti's fork of [digimata/parrot](https://github.com/digimata/parrot), a
fully local macOS dictation daemon. Hold a key, speak, release, and the
transcript appears at the cursor in any app.

This fork is optimized for Backslash dictation on Apple Silicon Macs:

- Backslash is the default push-to-talk key.
- Hold Backslash for ordinary push-to-talk dictation.
- Double-tap Backslash for hands-free dictation, then tap once to stop.
- Qwen3-ASR 1.7B MLX 8-bit is the default transcription model.
- A persistent MLX worker keeps Qwen loaded between recordings for lower latency.
- Transcription stays on the Mac. Audio is not sent to a cloud service.
- Bluetooth microphones are avoided automatically when a built-in Mac microphone
  is available, preventing headset call-mode transitions and "call ended" alerts.
- Shift-Backslash and modified shortcuts continue to work normally.
- A release-state fallback prevents a missed key-up from leaving recording active.

Parakeet TDT and WhisperKit models remain available as optional fallbacks.

## Requirements

- macOS 14 or later
- Apple Silicon, M1 or newer
- About 4 GB of free disk space for Qwen and its runtime
- Internet access during the initial model download
- Xcode Command Line Tools only if building from source

## Install the prebuilt release

```sh
curl -fsSL https://raw.githubusercontent.com/PaulScotti/parrot/main/scripts/install.sh | sh
parrot setup
parrot install --launch-at-login \
  --hotkey backslash \
  --model qwen3-asr-1.7b-mlx-8bit \
  --input-device automatic
```

The installer places the executable in `/opt/homebrew/bin` when that directory
exists, otherwise in `/usr/local/bin`. Qwen, its isolated Python runtime, support
scripts, caches, and logs live under `~/Library/Application Support/Parrot` by
default. Set `PARROT_HOME` before running the installer to choose another folder.

On first setup, grant `parrot` Microphone and Accessibility access in System
Settings. If macOS retains an obsolete Accessibility row after an update,
remove that row and add the exact installed executable again.

## Build from source

Install Apple's command-line developer tools and `uv` if needed:

```sh
xcode-select --install
brew install uv
```

Then clone, prepare Qwen, build, and install:

```sh
git clone https://github.com/PaulScotti/parrot.git
cd parrot
./scripts/setup-qwen-mlx.sh
swift build -c release
sudo mkdir -p /usr/local/bin
sudo install -m 755 .build/release/parrot /usr/local/bin/parrot
parrot setup
parrot install --launch-at-login \
  --hotkey backslash \
  --model qwen3-asr-1.7b-mlx-8bit \
  --input-device automatic \
  --home "$PWD"
```

Only the installed executable and the login LaunchAgent need to live outside
the project folder. The `--home` option keeps scripts, models, caches, temporary
audio, and logs together in the source checkout.

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
parrot                                  # run in the foreground with Qwen
parrot setup                            # configure permissions
parrot doctor                           # check permissions and hotkey setup
parrot models list                      # list available models
parrot models download qwen3-asr-1.7b-mlx-8bit
parrot --input-device system            # intentionally use the default mic
parrot --input-device built-in          # always use the Mac microphone
parrot install --uninstall              # remove the launch agent
```

`--input-device automatic` follows the system input unless it is Bluetooth. If
the default input is Bluetooth and the Mac has a built-in microphone, Parrot
uses the built-in microphone only for its own process. The system-wide input
and headset output remain unchanged.

## Stack

- Swift and Swift Package Manager for hotkeys, recording, UI, and text insertion
- Qwen3-ASR 1.7B 8-bit through MLX Audio for default local transcription
- A persistent JSON-lines worker in an isolated Python 3.12 environment
- FluidAudio with Parakeet TDT 0.6B v2 as an optional fallback
- WhisperKit as an optional fallback
- AVAudioEngine for microphone capture
- CGEventTap for the global hotkey
- CGEvent for text insertion

See [docs/architecture.md](docs/architecture.md) for implementation details.
The upstream project and this fork are distributed under the [MIT License](LICENSE).
