import ArgumentParser
import Foundation

/// Manage parrot's LaunchAgent so the daemon starts at login.
///
/// We deliberately do NOT use SMAppService.mainApp here — that requires a full
/// .app bundle. Since parrot ships as a single binary in /usr/local/bin, a
/// plain LaunchAgent plist is the simpler, more honest mechanism.
struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install or remove the launch-at-login LaunchAgent."
    )

    @Flag(name: .long, help: "Register parrot to start at login.")
    var launchAtLogin: Bool = false

    @Flag(name: .long, help: "Remove the launch-at-login agent.")
    var uninstall: Bool = false

    @Option(name: .long, help: "Push-to-talk key for the launch-at-login daemon.")
    var hotkey: Hotkey = .backslash

    @Option(
        name: .long,
        help: "Microphone selection for the launch-at-login daemon (automatic, system, or built-in)."
    )
    var inputDevice: AudioInputPreference = .automatic

    @Option(name: .long, help: "Folder containing Parrot logs and source checkout.")
    var home: String?

    @Option(name: .long, help: "Azure Speech resource name.")
    var azureResource: String = ParrotPaths.azureResource

    @Option(name: .long, help: "File containing the Azure Speech API key.")
    var azureKeyFile: String = ParrotPaths.azureKeyFile.path

    func run() throws {
        if launchAtLogin == uninstall {
            FileHandle.standardError.write(Data(
                "specify exactly one of --launch-at-login or --uninstall\n".utf8
            ))
            throw ExitCode(64)
        }

        if uninstall {
            try removeAgent()
        } else {
            try writeAgent()
        }
    }

    // MARK: -

    private static let label = "com.digimata.parrot"

    private var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist")
    }

    private func writeAgent() throws {
        let binary = try resolveBinaryPath()
        let parrotHome = URL(
            fileURLWithPath: home ?? ParrotPaths.home.path,
            isDirectory: true
        ).standardizedFileURL
        try FileManager.default.createDirectory(
            at: parrotHome.appendingPathComponent("runtime/logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        guard MAITranscriber.isValidResourceName(azureResource) else {
            FileHandle.standardError.write(Data("invalid Azure Speech resource: \(azureResource)\n".utf8))
            throw ExitCode(1)
        }
        let keyURL = URL(fileURLWithPath: azureKeyFile).standardizedFileURL
        guard ProcessInfo.processInfo.environment["AZURE_API_KEY"]?.isEmpty == false
            || FileManager.default.isReadableFile(atPath: keyURL.path) else {
            FileHandle.standardError.write(Data("Azure API key is not readable at \(keyURL.path)\n".utf8))
            throw ExitCode(1)
        }

        let arguments = [
            binary,
            "run",
            "--skip-doctor",
            "--hotkey", hotkey.rawValue,
            "--input-device", inputDevice.rawValue,
        ]
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false] as [String: Any],
            "ProcessType": "Interactive",
            "StandardOutPath": parrotHome.appendingPathComponent("runtime/logs/parrot.out.log").path,
            "StandardErrorPath": parrotHome.appendingPathComponent("runtime/logs/parrot.err.log").path,
            "EnvironmentVariables": [
                "PARROT_HOME": parrotHome.path,
                "PARROT_AZURE_RESOURCE": azureResource,
                "PARROT_AZURE_KEY_FILE": keyURL.path,
            ],
        ]

        let url = plistURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)

        // Best-effort bootstrap; ignore failure if already loaded.
        _ = runLaunchctl(["bootout", "gui/\(uid())", url.path])
        let result = runLaunchctl(["bootstrap", "gui/\(uid())", url.path])
        if result.status != 0 {
            FileHandle.standardError.write(Data(
                "warning: launchctl bootstrap exited \(result.status):\n\(result.stderr)\n".utf8
            ))
        }

        print("✓ launch-at-login installed")
        print("  plist:  \(url.path)")
        print("  binary: \(binary)")
        print("  hotkey: \(hotkey.displayName)")
        print("  model:  \(MAITranscriber.modelID)")
        print("  style:  \(MAITranscriber.style)")
        print("  lang:   \(MAITranscriber.language)")
        print("  Azure:  \(azureResource)")
        print("  key:    \(keyURL.path)")
        print("  input:  \(inputDevice.rawValue)")
        print("  home:   \(parrotHome.path)")
        print("  logs:   \(parrotHome.appendingPathComponent("runtime/logs").path)")
    }

    private func removeAgent() throws {
        let url = plistURL
        if FileManager.default.fileExists(atPath: url.path) {
            _ = runLaunchctl(["bootout", "gui/\(uid())", url.path])
            try FileManager.default.removeItem(at: url)
            print("✓ launch-at-login removed")
        } else {
            print("nothing to remove (no agent at \(url.path))")
        }
    }

    private func resolveBinaryPath() throws -> String {
        // Prefer the native Apple Silicon prefix, then the upstream install
        // path. This also makes launchd use the same binary found first on PATH.
        let candidates = ["/opt/homebrew/bin/parrot", "/usr/local/bin/parrot"]
        if let candidate = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return candidate
        }
        // Fall back to the running executable's resolved path.
        let argv0 = CommandLine.arguments.first ?? "parrot"
        if argv0.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: argv0) {
            FileHandle.standardError.write(Data(
            "note: no installed parrot binary found; using \(argv0)\n".utf8
            ))
            return argv0
        }
        FileHandle.standardError.write(Data(
            "couldn't locate the parrot binary. install it to /opt/homebrew/bin/parrot first.\n".utf8
        ))
        throw ExitCode(1)
    }

    private func uid() -> uid_t { getuid() }

    private func runLaunchctl(_ args: [String]) -> (status: Int32, stderr: String) {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = args
        let errPipe = Pipe()
        task.standardError = errPipe
        task.standardOutput = Pipe()
        do {
            try task.run()
        } catch {
            return (-1, "\(error)")
        }
        task.waitUntilExit()
        let err = String(
            data: errPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (task.terminationStatus, err)
    }
}
