import FluidAudio
import Foundation

actor ParakeetTranscriber: Transcriber {
    let modelID: String
    private let model: TranscriptionModel
    private var manager: AsrManager?

    init(model: TranscriptionModel) {
        self.modelID = model.id
        self.model = model
    }

    /// Loads the Core ML models into memory; downloads them first if needed.
    /// Parakeet v2 uses an int8 encoder on Apple's Neural Engine by default.
    func warmUp() async throws {
        if manager != nil { return }
        guard model.engineID == "v2" else {
            throw TranscriberError.unsupportedEngineID(model.engineID)
        }

        FileHandle.standardError.write(Data("loading \(model.id)...\n".utf8))
        let models = try await AsrModels.downloadAndLoad(
            version: .v2,
            encoderPrecision: .int8
        )
        let loadedManager = AsrManager(config: .default)
        try await loadedManager.loadModels(models)
        manager = loadedManager
        FileHandle.standardError.write(Data("✓ \(model.id) ready\n".utf8))
    }

    func transcribe(_ audio: [Float]) async throws -> String {
        if manager == nil { try await warmUp() }
        guard let manager else { throw TranscriberError.notLoaded }

        let decoderLayerCount = await manager.decoderLayerCount
        var decoderState = TdtDecoderState.make(decoderLayers: decoderLayerCount)
        let result = try await manager.transcribe(audio, decoderState: &decoderState)
        return Self.sanitize(result.text)
    }

    private static func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
