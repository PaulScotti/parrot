import AppKit
import ArgumentParser
import Foundation

@main
struct Parrot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parrot",
        abstract: "Minimal macOS dictation daemon. Hold the hotkey, speak, release.",
        subcommands: [Run.self, Setup.self, Doctor.self, Transcribe.self, Install.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the daemon (default)."
    )

    @Flag(name: .long, help: "Skip permission checks at startup.")
    var skipDoctor: Bool = false

    @Flag(name: .long, help: "Print every keyboard event the tap sees (debug).")
    var debugHotkey: Bool = false

    @Flag(name: .long, help: "Write each capture to /tmp/parrot-last.wav for inspection.")
    var dumpWav: Bool = false

    @Flag(name: .long, help: "Disable the on-screen recording overlay.")
    var noOverlay: Bool = false

    @Option(name: .long, help: "Push-to-talk key (fn, left-control, right-control, or backslash).")
    var hotkey: Hotkey = .backslash

    @Option(
        name: .long,
        help: "Microphone selection (automatic, system, or built-in). Automatic avoids Bluetooth call mode."
    )
    var inputDevice: AudioInputPreference = .automatic

    func run() throws {
        if !skipDoctor {
            let checks = DoctorReport.run(hotkey: hotkey)
            if !DoctorReport.allOK(checks) {
                FileHandle.standardError.write(Data("startup checks failed:\n".utf8))
                DoctorReport.print(checks)
                FileHandle.standardError.write(Data("\nfix the above or pass --skip-doctor\n".utf8))
                throw ExitCode(1)
            }
        }

        let transcriber: MAITranscriber
        do {
            transcriber = try MAITranscriber()
        } catch {
            FileHandle.standardError.write(Data(
                "Azure configuration failed: \(error.localizedDescription)\n".utf8
            ))
            throw ExitCode(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let monitor = HotkeyMonitor(hotkey: hotkey, debug: debugHotkey)
        let capture = AudioCapture(inputPreference: inputDevice)
        capture.onInputSelected = { device in
            let fallback = device.isBluetooth ? "" : " · Bluetooth call mode avoided"
            FileHandle.standardError.write(Data("audio input: \(device.name)\(fallback)\n".utf8))
        }
        let dumpWav = self.dumpWav
        let overlay: RecordingOverlay? = noOverlay ? nil : MainActor.assumeIsolated { RecordingOverlay() }
        if let overlay {
            capture.onLevel = { level in overlay.pushLevel(level) }
        }
        do {
            try capture.prepare()
        } catch {
            FileHandle.standardError.write(Data("audio input failed: \(error.localizedDescription)\n".utf8))
            throw ExitCode(1)
        }
        let menuBar = MainActor.assumeIsolated {
            MenuBarController(
                modelID: MAITranscriber.modelID,
                hotkeyName: hotkey.displayName,
                supportsHandsFree: hotkey == .backslash
            )
        }

        do {
            try monitor.start { event in
                switch event {
                case .recordingStarted:
                    do {
                        try capture.start()
                        FileHandle.standardError.write(Data("● recording\n".utf8))
                        MainActor.assumeIsolated {
                            overlay?.show(.recording)
                            menuBar.setRecording(true)
                        }
                    } catch {
                        FileHandle.standardError.write(Data("capture failed: \(error)\n".utf8))
                    }
                case .handsFreeStarted:
                    FileHandle.standardError.write(Data(
                        "↔ hands-free recording · tap backslash to stop\n".utf8
                    ))
                    MainActor.assumeIsolated {
                        menuBar.setHandsFreeRecording()
                    }
                case .recordingStopped:
                    let samples = capture.stop()
                    MainActor.assumeIsolated {
                        overlay?.show(.transcribing)
                        menuBar.setTranscribing()
                    }
                    let seconds = Double(samples.count) / AudioCapture.targetSampleRate
                    let rms = computeRMS(samples)
                    FileHandle.standardError.write(Data(
                        String(format: "○ captured %.2fs · rms %.3f\n", seconds, rms).utf8
                    ))
                    if dumpWav, !samples.isEmpty {
                        let path = "/tmp/parrot-last.wav"
                        do {
                            try WAVWriter.write(samples: samples, sampleRate: 16_000, to: path)
                            FileHandle.standardError.write(Data("  wrote \(path)\n".utf8))
                        } catch {
                            FileHandle.standardError.write(Data("  wav write failed: \(error)\n".utf8))
                        }
                    }
                    guard !samples.isEmpty else {
                        MainActor.assumeIsolated {
                            overlay?.hide()
                            menuBar.setRecording(false)
                        }
                        return
                    }
                    Task {
                        let started = Date()
                        do {
                            let text = try await transcriber.transcribe(samples)
                            let elapsed = Date().timeIntervalSince(started)
                            FileHandle.standardError.write(Data(
                                String(format: "→ %.2fs · %@\n", elapsed, text).utf8
                            ))
                            await MainActor.run {
                                TextInjector.inject(text)
                                overlay?.hide()
                                menuBar.setRecording(false)
                            }
                        } catch {
                            FileHandle.standardError.write(Data("transcription failed: \(error)\n".utf8))
                            await MainActor.run {
                                overlay?.hide()
                                menuBar.setRecording(false)
                            }
                        }
                    }
                }
            }
        } catch {
            FileHandle.standardError.write(Data("failed to register hotkey tap: \(error)\n".utf8))
            FileHandle.standardError.write(Data("run `parrot setup` to configure permissions.\n".utf8))
            throw ExitCode(1)
        }

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            FileHandle.standardError.write(Data("\nshutting down\n".utf8))
            monitor.stop()
            NSApp.terminate(nil)
        }
        sigint.resume()
        signal(SIGINT, SIG_IGN)

        let gesture = hotkey == .backslash ? "hold or double-tap" : "hold"
        FileHandle.standardError.write(Data(
            "listening on \(hotkey.displayName.lowercased()) \(gesture) · model: \(MAITranscriber.modelID) · style: \(MAITranscriber.style) · language: \(MAITranscriber.language) · ^C to quit\n".utf8
        ))
        app.run()
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check microphone, accessibility, and hotkey configuration."
    )

    @Option(name: .long, help: "Push-to-talk key (fn, left-control, right-control, or backslash).")
    var hotkey: Hotkey = .backslash

    func run() throws {
        let checks = DoctorReport.run(hotkey: hotkey)
        DoctorReport.print(checks)
        if !DoctorReport.allOK(checks) {
            throw ExitCode(1)
        }
    }
}

struct Transcribe: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Transcribe a WAV file with the configured Azure service."
    )

    @Argument(help: "Path to a WAV audio file.")
    var file: String

    func run() throws {
        let fileURL = URL(fileURLWithPath: file).standardizedFileURL
        let wav: Data
        do {
            wav = try Data(contentsOf: fileURL)
        } catch {
            FileHandle.standardError.write(Data("could not read \(fileURL.path)\n".utf8))
            throw ExitCode(1)
        }

        guard wav.starts(with: Data("RIFF".utf8)) else {
            FileHandle.standardError.write(Data("input must be a WAV file\n".utf8))
            throw ExitCode(1)
        }

        do {
            let transcriber = try MAITranscriber()
            let semaphore = DispatchSemaphore(value: 0)
            var result: Result<String, Error>?
            Task.detached {
                do {
                    result = .success(try await transcriber.transcribeWAV(wav))
                } catch {
                    result = .failure(error)
                }
                semaphore.signal()
            }
            semaphore.wait()
            print(try result!.get())
        } catch {
            FileHandle.standardError.write(Data("transcription failed: \(error.localizedDescription)\n".utf8))
            throw ExitCode(1)
        }
    }
}
