# Architecture

## Runtime goals

1. Local macOS dictation with no cloud transcription.
2. Backslash hold-to-talk plus a double-tap hands-free latch.
3. Process-local built-in microphone selection when the system input is Bluetooth.
4. Qwen3-ASR 1.7B accelerated by MLX on Apple Silicon.
5. One persistent model worker so every recording does not reload 2.46 GB of weights.
6. Optional Parakeet and WhisperKit fallbacks.

## Process layout

```text
Backslash events
      |
      v
HotkeyMonitor -> AudioCapture -> 16 kHz mono samples
                                     |
                                     v
                               temporary WAV
                                     |
                                     v
Swift Parrot process <== JSON lines ==> persistent Python worker
                                             |
                                             v
                                  Qwen3-ASR 1.7B 8-bit
                                      through MLX Audio
                                             |
                                             v
TextInjector <------------------------- transcript
```

The Swift process owns macOS integration: permissions, global keyboard events,
audio capture, the recording overlay, the menu-bar item, and Unicode text
insertion. The Python worker owns only Qwen inference. It is a child process of
Parrot, reads requests from standard input, and writes structured responses to
standard output. It exits when Parrot closes its input pipe.

## Main components

### `Parrot.swift`

Defines the CLI and daemon. The default model is the registry's recommended
entry. Startup warms the selected transcriber before the event loop begins, so
the first Backslash press is ready to record.

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

### `QwenMLXTranscriber`

The Swift transcriber starts `scripts/qwen_mlx_worker.py` with the isolated
Python runtime at `runtime/qwen-mlx/venv`. Each recording is written to a
temporary PCM WAV under `runtime/tmp`, passed to the worker, and removed after
the response. The worker loads `mlx-community/Qwen3-ASR-1.7B-8bit` once and
reuses it for every recording in that Parrot session.

The protocol is newline-delimited JSON:

```json
{"type":"transcribe","id":"request-id","audio":"/path/capture.wav","language":"English"}
{"type":"result","id":"request-id","text":"Recognized speech."}
```

Standard output is reserved for protocol messages. Library diagnostics and
tracebacks go to standard error, which is captured by the LaunchAgent log.

### Fallback transcribers

- `ParakeetTranscriber` uses FluidAudio and Core ML.
- `WhisperKitTranscriber` uses WhisperKit and Core ML.

Both remain selectable with `--model`, but Qwen is the recommended default.

### `TextInjector`

Posts the transcript at the active cursor using Core Graphics keyboard events.
Secure text fields and a small number of application-specific editors can reject
synthetic input because of macOS platform restrictions.

### `RecordingOverlay` and `MenuBarController`

The overlay shows recording and transcription state without taking focus. The
menu-bar item exposes the current model and gesture, reports state, and provides
a Quit command. Parrot runs with the AppKit accessory activation policy, so it
does not appear in the Dock.

## Model registry

The built-in registry currently exposes:

| Engine | Model ID | Approximate model size | Default |
|---|---|---:|---|
| MLX Audio | `qwen3-asr-1.7b-mlx-8bit` | 2.46 GB | Yes |
| FluidAudio | `parakeet-tdt-0.6b-v2` | 452 MB | No |
| WhisperKit | `whisper-base.en` | 145 MB | No |
| WhisperKit | `whisper-small.en` | 488 MB | No |
| WhisperKit | `whisper-large-v3-turbo` | 1.62 GB | No |

Adding an engine requires a new `Transcriber` conformance and an `Engine` enum
case. Adding another model for an existing engine requires a registry entry.

## Storage layout

`PARROT_HOME` is the root for mutable and support data. If it is not set, Parrot
uses `~/My Drive/Projects/parrot` when that directory exists, then falls back to
`~/Library/Application Support/Parrot`.

```text
PARROT_HOME/
  scripts/
    qwen_mlx_worker.py
    qwen-mlx-requirements.lock
    setup-qwen-mlx.sh
  models/
    huggingface/
  runtime/
    qwen-mlx/python/
    qwen-mlx/venv/
    caches/
    logs/
    tmp/
```

The source checkout can itself be `PARROT_HOME`, keeping code and data together.
Only the executable on the shell path and the login LaunchAgent need to live
elsewhere.

## Login launch

`parrot install --launch-at-login` writes
`~/Library/LaunchAgents/com.digimata.parrot.plist`. The plist stores the chosen
hotkey, input device, model, `PARROT_HOME`, cache environment, and log paths. It
uses the exact installed executable path to keep macOS Accessibility identity
stable across logins.

## Data flow

1. Launchd starts the Swift executable.
2. Parrot starts the MLX worker and waits for its ready response.
3. The worker loads Qwen from the local Hugging Face cache.
4. The user holds or double-taps Backslash.
5. `AudioCapture` records with the selected process-local microphone.
6. Stopping records a temporary WAV and sends its path to the worker.
7. Qwen returns text while remaining resident for the next request.
8. Parrot deletes the WAV and injects the text at the current cursor.

No recorded audio or transcript is retained by the normal runtime.

## Build and release

`swift build -c release` produces the arm64 executable. The release workflow
packages that executable together with the Qwen worker, pinned dependency lock,
and runtime setup script. The installer places the executable on `PATH`, copies
the support scripts into `PARROT_HOME`, creates the isolated Python 3.12
environment, and downloads the MLX model on first installation.
