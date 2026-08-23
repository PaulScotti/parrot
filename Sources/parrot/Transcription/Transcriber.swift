import Foundation

protocol Transcriber: Sendable {
    var modelID: String { get }
    func warmUp() async throws
    func transcribe(_ audio: [Float]) async throws -> String
}

enum TranscriberFactory {
    static func make(model: TranscriptionModel) -> any Transcriber {
        switch model.engine {
        case .whisperKit:
            return WhisperKitTranscriber(model: model)
        case .parakeet:
            return ParakeetTranscriber(model: model)
        }
    }
}
