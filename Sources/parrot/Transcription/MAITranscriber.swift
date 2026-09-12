import Foundation

actor MAITranscriber {
    static let modelID = "MAI-Transcribe-2"
    static let style = "clean"
    static let language = "auto"

    private static let apiVersion = "2025-10-15"
    private static let retryDelays: [TimeInterval] = [2, 5]

    private let endpoint: URL
    private let apiKey: String
    private let session: URLSession

    init(
        resource: String = ParrotPaths.azureResource,
        keyFile: URL = ParrotPaths.azureKeyFile
    ) throws {
        guard Self.isValidResourceName(resource) else {
            throw MAITranscriptionError.invalidResource(resource)
        }

        let environmentKey = ProcessInfo.processInfo.environment["AZURE_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentKey, !environmentKey.isEmpty {
            apiKey = environmentKey
        } else {
            do {
                let fileKey = try String(contentsOf: keyFile, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fileKey.isEmpty else {
                    throw MAITranscriptionError.emptyKeyFile(keyFile.path)
                }
                apiKey = fileKey
            } catch let error as MAITranscriptionError {
                throw error
            } catch {
                throw MAITranscriptionError.keyFileUnavailable(keyFile.path)
            }
        }

        guard let endpoint = URL(
            string: "https://\(resource).cognitiveservices.azure.com/speechtotext/transcriptions:transcribe?api-version=\(Self.apiVersion)"
        ) else {
            throw MAITranscriptionError.invalidResource(resource)
        }
        self.endpoint = endpoint

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 65
        configuration.timeoutIntervalForResource = 75
        session = URLSession(configuration: configuration)
    }

    func transcribe(_ audio: [Float]) async throws -> String {
        let wav = WAVWriter.data(samples: audio, sampleRate: Int(AudioCapture.targetSampleRate))
        return try await transcribeWAV(wav)
    }

    func transcribeWAV(_ wav: Data) async throws -> String {
        var totalDelay: TimeInterval = 0

        for attempt in 0...Self.retryDelays.count {
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: makeRequest(wav: wav))
            } catch let error as URLError where error.code == .timedOut {
                throw MAITranscriptionError.timedOut
            } catch {
                throw MAITranscriptionError.unreachable
            }

            guard let http = response as? HTTPURLResponse else {
                throw MAITranscriptionError.invalidResponse
            }

            if http.statusCode == 429, attempt < Self.retryDelays.count {
                let requestedDelay = Self.retryAfterSeconds(http.value(forHTTPHeaderField: "Retry-After"))
                let delay = requestedDelay ?? Self.retryDelays[attempt]
                guard totalDelay + delay <= 15 else {
                    throw MAITranscriptionError.rateLimited
                }
                totalDelay += delay
                FileHandle.standardError.write(Data(
                    String(format: "Azure rate limit · retrying in %.0fs\n", delay).utf8
                ))
                try await Task.sleep(for: .seconds(delay))
                continue
            }

            guard (200..<300).contains(http.statusCode) else {
                throw MAITranscriptionError.httpStatus(http.statusCode)
            }

            return try Self.transcript(from: data)
        }

        throw MAITranscriptionError.rateLimited
    }

    private func makeRequest(wav: Data) throws -> URLRequest {
        let boundary = "Parrot-\(UUID().uuidString)"
        let definition: [String: Any] = [
            "enhancedMode": [
                "enabled": true,
                "model": Self.modelID,
                "modelOptions": ["transcribeStyle": Self.style],
            ] as [String: Any],
        ]
        let definitionData = try JSONSerialization.data(withJSONObject: definition)

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(wav)
        body.append("\r\n--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"definition\"\r\n")
        body.append("Content-Type: application/json\r\n\r\n")
        body.append(definitionData)
        body.append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private static func transcript(from data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let phrases = json["combinedPhrases"] as? [[String: Any]],
            phrases.allSatisfy({ $0["text"] is String })
        else {
            throw MAITranscriptionError.invalidResponse
        }

        return phrases
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidResourceName(_ resource: String) -> Bool {
        guard !resource.isEmpty, resource.count <= 63 else { return false }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "-"))
        return resource.unicodeScalars.allSatisfy(allowed.contains)
            && resource.first != "-"
            && resource.last != "-"
    }

    private static func retryAfterSeconds(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite {
            return max(0, seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }
}

private enum MAITranscriptionError: LocalizedError {
    case invalidResource(String)
    case keyFileUnavailable(String)
    case emptyKeyFile(String)
    case timedOut
    case unreachable
    case invalidResponse
    case rateLimited
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResource(let resource):
            return "invalid Azure Speech resource name: \(resource)"
        case .keyFileUnavailable(let path):
            return "Azure API key not found at \(path)"
        case .emptyKeyFile(let path):
            return "Azure API key file is empty at \(path)"
        case .timedOut:
            return "Azure transcription timed out"
        case .unreachable:
            return "could not reach Azure transcription"
        case .invalidResponse:
            return "Azure returned an invalid transcription response"
        case .rateLimited:
            return "MAI-Transcribe-2 is being rate limited by Azure"
        case .httpStatus(let status):
            switch status {
            case 400: return "Azure rejected the recording or transcription settings (400)"
            case 401: return "Azure rejected the API key for this resource (401)"
            case 403: return "Azure denied Speech access for this resource (403)"
            case 404: return "Azure could not find MAI-Transcribe-2 for this resource (404)"
            case 429: return "MAI-Transcribe-2 is being rate limited by Azure (429)"
            default: return "Azure transcription failed (\(status))"
            }
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(contentsOf: string.utf8)
    }
}
