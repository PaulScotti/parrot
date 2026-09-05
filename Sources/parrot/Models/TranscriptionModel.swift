import Foundation

enum Engine: String, Codable {
    case whisperKit
    case parakeet
    case qwenMLX
}

struct TranscriptionModel: Codable {
    let id: String
    let displayName: String
    let engine: Engine
    /// Engine-specific identifier, such as a Core ML name or Hugging Face repo.
    let engineID: String
    let sizeMB: Int
    let languages: [String]
    let recommended: Bool
}

struct ModelsManifest: Codable {
    let models: [TranscriptionModel]
}
