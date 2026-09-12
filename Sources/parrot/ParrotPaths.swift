import Foundation

enum ParrotPaths {
    private static let environment = ProcessInfo.processInfo.environment

    static var home: URL {
        if let configured = environment["PARROT_HOME"], !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }

        let preferred = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("My Drive/Projects/parrot", isDirectory: true)
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }

        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Parrot", isDirectory: true)
    }

    static var azureResource: String {
        environment["PARROT_AZURE_RESOURCE"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "korean-mai-eastus"
    }

    static var azureKeyFile: URL {
        if let configured = environment["PARROT_AZURE_KEY_FILE"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }

        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let standard = userHome.appendingPathComponent(".config/parrot/azure-api-key")
        if FileManager.default.fileExists(atPath: standard.path) {
            return standard
        }

        let sharedKoreanAppKey = userHome.appendingPathComponent(".pi/korean/audio/azure-api-key")
        if FileManager.default.fileExists(atPath: sharedKoreanAppKey.path) {
            return sharedKoreanAppKey
        }

        return standard
    }

    static var logs: URL {
        home.appendingPathComponent("runtime/logs", isDirectory: true)
    }

    static func ensureRuntimeDirectories() throws {
        try FileManager.default.createDirectory(
            at: logs,
            withIntermediateDirectories: true
        )
    }
}
