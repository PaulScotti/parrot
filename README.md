# parrot

Paul Scotti's fork of [digimata/parrot](https://github.com/digimata/parrot), a
macOS dictation daemon. Hold a key, speak, release, and the transcript appears
at the cursor in any app.

This fork is configured for Backslash dictation and Microsoft
MAI-Transcribe-2 through Azure Speech:

- Backslash is the default push-to-talk key.
- Hold Backslash for ordinary push-to-talk dictation.
- Double-tap Backslash for hands-free dictation, then tap once to stop.
- MAI-Transcribe-2 is the only transcription model.
- The transcription style is always `clean`.
- Language detection is automatic, including English, Korean, and switching
  between them.
- Bluetooth microphones are avoided automatically when a built-in Mac
  microphone is available, preventing headset call-mode transitions.
- Shift-Backslash and modified shortcuts continue to work normally.
- A release-state fallback prevents a missed key-up from leaving recording
  active.

## Requirements

- macOS 14 or later
- Apple Silicon, M1 or newer, for the prebuilt release
- An Azure Speech resource with MAI-Transcribe-2 access
- The resource name and one API key
- Xcode Command Line Tools only if building from source

## Install the prebuilt release

```sh
curl -fsSL https://raw.githubusercontent.com/PaulScotti/parrot/main/scripts/install.sh | sh
mkdir -p "$HOME/.config/parrot"
read -s "AZURE_KEY?Paste your Azure Speech key: "; echo
printf '%s\n' "$AZURE_KEY" > "$HOME/.config/parrot/azure-api-key"
unset AZURE_KEY
chmod 600 "$HOME/.config/parrot/azure-api-key"
parrot setup
parrot install --launch-at-login \
  --hotkey backslash \
  --input-device automatic \
  --azure-resource YOUR_AZURE_RESOURCE \
  --azure-key-file "$HOME/.config/parrot/azure-api-key"
```

Replace `YOUR_AZURE_RESOURCE` with the resource name shown in the Azure portal.
The installer places the executable in `/opt/homebrew/bin` when that directory
exists, otherwise in `/usr/local/bin`.

On first setup, grant `parrot` Microphone and Accessibility access in System
Settings. If macOS retains an obsolete Accessibility row after an update,
remove that row and add the exact installed executable again.

## Build from source

```sh
xcode-select --install
git clone https://github.com/PaulScotti/parrot.git
cd parrot
swift build -c release
sudo mkdir -p /opt/homebrew/bin
sudo install -m 755 .build/release/parrot /opt/homebrew/bin/parrot
parrot setup
parrot install --launch-at-login \
  --hotkey backslash \
  --input-device automatic \
  --azure-resource YOUR_AZURE_RESOURCE \
  --azure-key-file "$HOME/.config/parrot/azure-api-key" \
  --home "$PWD"
```

## How to use

1. Click into any text field.
2. Hold Backslash while speaking and release it, or double-tap Backslash to
   start hands-free dictation.
3. When hands-free dictation is active, tap Backslash once to stop.
4. Parrot sends the recording to Azure and inserts the returned text at the
   cursor.

The menu-bar item and recording pill show whether Parrot is recording or
transcribing.

## Useful commands

```sh
parrot                                  # run in the foreground
parrot setup                            # configure permissions and check Azure
parrot doctor                           # check permissions and Azure setup
parrot transcribe recording.wav         # transcribe a WAV file for diagnostics
parrot --input-device system            # intentionally use the default mic
parrot --input-device built-in          # always use the Mac microphone
parrot install --uninstall              # remove the launch agent
```

`--input-device automatic` follows the system input unless it is Bluetooth. If
the default input is Bluetooth and the Mac has a built-in microphone, Parrot
uses the built-in microphone only for its own process. The system-wide input
and headset output remain unchanged.

## Stack

- Swift and Swift Package Manager for the CLI and macOS integration
- Microsoft MAI-Transcribe-2 through Azure Speech fast transcription
- AVAudioEngine for microphone capture
- CGEventTap for the global hotkey
- CGEvent for text insertion

See [docs/architecture.md](docs/architecture.md) for implementation details.
The upstream project and this fork are distributed under the [MIT License](LICENSE).
