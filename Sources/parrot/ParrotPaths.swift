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

    static var qwenPython: URL {
        if let configured = environment["PARROT_QWEN_PYTHON"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        return home.appendingPathComponent("runtime/qwen-mlx/venv/bin/python")
    }

    static var qwenWorker: URL {
        if let configured = environment["PARROT_QWEN_WORKER"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        return home.appendingPathComponent("scripts/qwen_mlx_worker.py")
    }

    static var modelCache: URL {
        home.appendingPathComponent("models/huggingface", isDirectory: true)
    }

    static var runtimeCache: URL {
        home.appendingPathComponent("runtime/caches", isDirectory: true)
    }

    static var temporaryAudio: URL {
        home.appendingPathComponent("runtime/tmp", isDirectory: true)
    }

    static var logs: URL {
        home.appendingPathComponent("runtime/logs", isDirectory: true)
    }

    static func ensureRuntimeDirectories() throws {
        for directory in [modelCache, runtimeCache, temporaryAudio, logs] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }
}
