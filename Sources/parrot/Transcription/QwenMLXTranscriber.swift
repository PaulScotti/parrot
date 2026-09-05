import Foundation

actor QwenMLXTranscriber: Transcriber {
    let modelID: String
    private let model: TranscriptionModel
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var outputBuffer = Data()

    init(model: TranscriptionModel) {
        self.modelID = model.id
        self.model = model
    }

    func warmUp() async throws {
        if process?.isRunning == true { return }

        try ParrotPaths.ensureRuntimeDirectories()
        guard FileManager.default.isExecutableFile(atPath: ParrotPaths.qwenPython.path) else {
            throw QwenMLXError.runtimeMissing(ParrotPaths.qwenPython.path)
        }
        guard FileManager.default.fileExists(atPath: ParrotPaths.qwenWorker.path) else {
            throw QwenMLXError.workerMissing(ParrotPaths.qwenWorker.path)
        }

        FileHandle.standardError.write(Data("loading \(model.id)...\n".utf8))

        let worker = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        worker.executableURL = ParrotPaths.qwenPython
        worker.arguments = [
            ParrotPaths.qwenWorker.path,
            "--model", model.engineID,
        ]
        worker.standardInput = inputPipe
        worker.standardOutput = outputPipe
        worker.standardError = FileHandle.standardError

        var environment = ProcessInfo.processInfo.environment
        environment["HF_HOME"] = ParrotPaths.modelCache.path
        environment["HF_HUB_CACHE"] = ParrotPaths.modelCache
            .appendingPathComponent("hub", isDirectory: true).path
        environment["XDG_CACHE_HOME"] = ParrotPaths.runtimeCache.path
        environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        worker.environment = environment

        do {
            try worker.run()
        } catch {
            throw QwenMLXError.launchFailed(error.localizedDescription)
        }

        process = worker
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        outputBuffer.removeAll(keepingCapacity: true)

        let response = try readResponse()
        guard response.type == "ready" else {
            stopWorker()
            throw response.asError
        }
        FileHandle.standardError.write(Data("✓ \(model.id) ready via MLX\n".utf8))
    }

    func transcribe(_ audio: [Float]) async throws -> String {
        if process?.isRunning != true { try await warmUp() }
        guard let input else { throw QwenMLXError.workerExited }

        let requestID = UUID().uuidString
        let audioURL = ParrotPaths.temporaryAudio
            .appendingPathComponent("capture-\(requestID).wav")
        try WAVWriter.write(
            samples: audio,
            sampleRate: Int(AudioCapture.targetSampleRate),
            to: audioURL.path
        )
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let request: [String: Any] = [
            "type": "transcribe",
            "id": requestID,
            "audio": audioURL.path,
            "language": "English",
        ]
        var data = try JSONSerialization.data(withJSONObject: request)
        data.append(0x0A)
        do {
            try input.write(contentsOf: data)
        } catch {
            stopWorker()
            throw QwenMLXError.workerExited
        }

        let response = try readResponse()
        guard response.type == "result", response.id == requestID, let text = response.text else {
            throw response.asError
        }
        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shutDown() {
        stopWorker()
    }

    private func readResponse() throws -> WorkerResponse {
        guard let output else { throw QwenMLXError.workerExited }
        while outputBuffer.firstRange(of: Data([0x0A])) == nil {
            let chunk = output.availableData
            guard !chunk.isEmpty else {
                stopWorker()
                throw QwenMLXError.workerExited
            }
            outputBuffer.append(chunk)
        }
        let newline = outputBuffer.firstRange(of: Data([0x0A]))!.lowerBound
        let line = outputBuffer.prefix(upTo: newline)
        outputBuffer.removeSubrange(...newline)
        do {
            return try JSONDecoder().decode(WorkerResponse.self, from: line)
        } catch {
            throw QwenMLXError.invalidResponse(String(decoding: line, as: UTF8.self))
        }
    }

    private func stopWorker() {
        try? input?.close()
        try? output?.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil
        input = nil
        output = nil
        outputBuffer.removeAll(keepingCapacity: false)
    }
}

private struct WorkerResponse: Decodable {
    let type: String
    let id: String?
    let text: String?
    let error: String?

    var asError: QwenMLXError {
        .workerError(error ?? "unexpected worker response: \(type)")
    }
}

private enum QwenMLXError: LocalizedError {
    case runtimeMissing(String)
    case workerMissing(String)
    case launchFailed(String)
    case workerExited
    case workerError(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing(let path):
            return "Qwen MLX runtime missing at \(path); run scripts/setup-qwen-mlx.sh"
        case .workerMissing(let path):
            return "Qwen MLX worker missing at \(path)"
        case .launchFailed(let message):
            return "could not launch Qwen MLX worker: \(message)"
        case .workerExited:
            return "Qwen MLX worker exited unexpectedly"
        case .workerError(let message):
            return "Qwen MLX transcription failed: \(message)"
        case .invalidResponse(let response):
            return "invalid response from Qwen MLX worker: \(response)"
        }
    }
}
