# Architecture

## Runtime goals

1. Backslash hold-to-talk plus a double-tap hands-free latch.
2. Process-local built-in microphone selection when the system input is Bluetooth.
3. Microsoft MAI-Transcribe-2 through Azure Speech fast transcription.
4. Clean transcription style with automatic language detection.
5. No local model runtime or model selection path.

## Process layout

```text
Backslash events
      |
      v
HotkeyMonitor -> AudioCapture -> 16 kHz mono samples
                                     |
                                     v
                              PCM WAV in memory
                                     |
                                     v
                    Azure Speech fast transcription
                       MAI-Transcribe-2, clean, auto
                                     |
                                     v
TextInjector <------------------ transcript
```

The Swift process owns permissions, global keyboard events, audio capture, WAV
encoding, the Azure request, the recording overlay, the menu-bar item, and
Unicode text insertion. There is no Python worker or model cache.

## Main components

### `Parrot.swift`

Defines the CLI and daemon. It constructs the Azure transcriber, prepares the
selected microphone, and starts the hotkey event loop. The `transcribe`
subcommand sends a supplied WAV file through the same Azure client for direct
diagnostics.

### `HotkeyMonitor` and `BackslashActivation`

`HotkeyMonitor` uses a `CGEventTap`, which requires Accessibility permission.
For ANSI keycode 42, a long press behaves as push-to-talk. Two brief taps within
the configured window latch recording, and the next tap stops it. Unmodified
Backslash is suppressed while it controls Parrot. Shift-Backslash and modified
shortcuts pass through normally.

### `AudioCapture`

`AVAudioEngine` records 16 kHz mono `Float32` samples. Automatic input selection
uses the system input unless it is Bluetooth. When Bluetooth is selected and a
built-in microphone exists, Parrot chooses the built-in microphone only for its
own process. This avoids putting Bose and similar headsets into call mode.

### `MAITranscriber`

The transcriber converts samples to a 16-bit PCM WAV in memory and sends a
multipart request to the Azure Speech fast transcription endpoint. Its request
definition always enables `MAI-Transcribe-2` with
`modelOptions.transcribeStyle` set to `clean`. It omits `locales`, which enables
automatic language identification and code switching.

Azure credentials are read from `AZURE_API_KEY` or the file selected by
`PARROT_AZURE_KEY_FILE`. The resource name comes from `PARROT_AZURE_RESOURCE`.
The key is never copied into the LaunchAgent property list or logs.

### `TextInjector`

Posts the transcript at the active cursor using Core Graphics keyboard events.
Secure text fields and a small number of application-specific editors can reject
synthetic input because of macOS platform restrictions.

### `RecordingOverlay` and `MenuBarController`

The overlay shows recording and transcription state without taking focus. The
menu-bar item displays MAI-Transcribe-2 and the current gesture, reports state,
and provides a Quit command. Parrot uses the AppKit accessory activation policy,
so it does not appear in the Dock.

## Storage layout

`PARROT_HOME` controls the log location. If it is not set, Parrot uses
`~/My Drive/Projects/parrot` when that directory exists, then falls back to
`~/Library/Application Support/Parrot`.

```text
PARROT_HOME/
  runtime/
    logs/
```

The Azure key normally lives at `~/.config/parrot/azure-api-key`. Parrot also
recognizes the existing Korean app key at `~/.pi/korean/audio/azure-api-key`.

## Login launch

`parrot install --launch-at-login` writes
`~/Library/LaunchAgents/com.digimata.parrot.plist`. The property list stores the
hotkey, input device, `PARROT_HOME`, Azure resource name, key file path, and log
paths. The secret remains inside the key file. The agent uses the exact installed
executable path so macOS Accessibility permission remains stable across logins.

## Data flow

1. Launchd starts the Swift executable.
2. Parrot validates the Azure resource and key file.
3. The user holds or double-taps Backslash.
4. `AudioCapture` records with the selected process-local microphone.
5. `MAITranscriber` encodes a WAV in memory and sends it to Azure.
6. Azure returns a clean transcript with automatic language detection.
7. Parrot injects the transcript at the current cursor.

Parrot does not write recordings or transcripts to disk during normal use.

## Build and release

`swift build -c release` produces the executable. The release workflow packages
that single binary. The installer places it on `PATH`; no model download or
Python runtime is required.
