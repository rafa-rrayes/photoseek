import Foundation

public actor GeminiClient {
    private let session: URLSession
    private let videoSession: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        // Video uploads + embeds can take longer; use a generous timeout.
        let videoConfig = URLSessionConfiguration.default
        videoConfig.timeoutIntervalForRequest = 180
        videoConfig.timeoutIntervalForResource = 600
        self.videoSession = URLSession(configuration: videoConfig)
    }

    public func embedText(_ text: String, apiKey: String) async throws -> [Float] {
        let body: [String: Any] = [
            "content": ["parts": [["text": text]]],
            "taskType": "RETRIEVAL_QUERY",
            "output_dimensionality": 768
        ]
        return try await callEmbed(body: body, apiKey: apiKey, useVideoSession: false)
    }

    public func embedImage(_ jpegData: Data, apiKey: String) async throws -> [Float] {
        let body: [String: Any] = [
            "content": ["parts": [
                ["inline_data": [
                    "mime_type": "image/jpeg",
                    "data": jpegData.base64EncodedString()
                ]]
            ]],
            "taskType": "RETRIEVAL_DOCUMENT",
            "output_dimensionality": 768
        ]
        return try await callEmbed(body: body, apiKey: apiKey, useVideoSession: false)
    }

    public func embedVideo(_ videoData: Data, mimeType: String, apiKey: String) async throws -> [Float] {
        let body: [String: Any] = [
            "content": ["parts": [
                ["inline_data": [
                    "mime_type": mimeType,
                    "data": videoData.base64EncodedString()
                ]]
            ]],
            "taskType": "RETRIEVAL_DOCUMENT",
            "output_dimensionality": 768
        ]
        return try await callEmbed(body: body, apiKey: apiKey, useVideoSession: true)
    }

    public func embedVideoByFileUri(_ fileUri: String, mimeType: String, apiKey: String) async throws -> [Float] {
        let body: [String: Any] = [
            "content": ["parts": [
                ["file_data": [
                    "mime_type": mimeType,
                    "file_uri": fileUri
                ]]
            ]],
            "taskType": "RETRIEVAL_DOCUMENT",
            "output_dimensionality": 768
        ]
        return try await callEmbed(body: body, apiKey: apiKey, useVideoSession: true)
    }

    /// Uploaded file handle — `name` is used to delete and poll, `uri` is passed to embedContent.
    public struct UploadedFile: Sendable {
        public let name: String
        public let uri: String
    }

    /// Resumable upload to the Gemini Files API. Returns the file name + URI once the
    /// file transitions to ACTIVE state (videos are PROCESSING for a few seconds first).
    public func uploadFile(_ data: Data, mimeType: String, displayName: String, apiKey: String) async throws -> UploadedFile {
        // Step 1: start the resumable session.
        let startURL = URL(string: "https://generativelanguage.googleapis.com/upload/v1beta/files")!
        var startReq = URLRequest(url: startURL)
        startReq.httpMethod = "POST"
        startReq.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        startReq.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startReq.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startReq.setValue(String(data.count), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startReq.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let metadata: [String: Any] = ["file": ["display_name": displayName]]
        startReq.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        let (startData, startResp) = try await runRequest(startReq, session: videoSession)
        guard let http = startResp as? HTTPURLResponse else { throw GeminiError.unknown(0) }
        guard http.statusCode == 200 else {
            try mapError(code: http.statusCode, body: startData)
            throw GeminiError.unknown(http.statusCode)
        }
        guard let uploadURLString = http.value(forHTTPHeaderField: "X-Goog-Upload-URL")
                                  ?? http.value(forHTTPHeaderField: "x-goog-upload-url"),
              let uploadURL = URL(string: uploadURLString) else {
            throw GeminiError.unknown(http.statusCode)
        }

        // Step 2: send the bytes and finalize.
        var uploadReq = URLRequest(url: uploadURL)
        uploadReq.httpMethod = "POST"
        uploadReq.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadReq.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadReq.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        uploadReq.httpBody = data

        let (uploadData, uploadResp) = try await runRequest(uploadReq, session: videoSession)
        guard let http2 = uploadResp as? HTTPURLResponse, http2.statusCode == 200 else {
            let code = (uploadResp as? HTTPURLResponse)?.statusCode ?? 0
            try mapError(code: code, body: uploadData)
            throw GeminiError.unknown(code)
        }

        let result = try JSONDecoder().decode(FileUploadResponse.self, from: uploadData)
        let file = result.file

        // Videos start as PROCESSING; poll until ACTIVE.
        if file.state != "ACTIVE" {
            try await waitForFileActive(name: file.name, apiKey: apiKey)
        }

        return UploadedFile(name: file.name, uri: file.uri)
    }

    public func deleteFile(name: String, apiKey: String) async {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(name)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        _ = try? await videoSession.data(for: req)
    }

    // MARK: - Private

    private func waitForFileActive(name: String, apiKey: String, maxAttempts: Int = 60) async throws {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(name)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        for _ in 0..<maxAttempts {
            try await Task.sleep(for: .seconds(2))
            let (data, response) = try await runRequest(req, session: videoSession)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
            let file = try? JSONDecoder().decode(FileMetadata.self, from: data)
            switch file?.state {
            case "ACTIVE":
                return
            case "FAILED":
                throw GeminiError.serverError
            default:
                continue
            }
        }
        throw GeminiError.networkTimeout
    }

    private func callEmbed(body: [String: Any], apiKey: String, useVideoSession: Bool) async throws -> [Float] {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-2-preview:embedContent")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await runRequest(request, session: useVideoSession ? videoSession : session)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try mapError(code: http.statusCode, body: data)
            throw GeminiError.unknown(http.statusCode)
        }

        let result = try JSONDecoder().decode(EmbedResponse.self, from: data)
        return result.embedding.values
    }

    private func runRequest(_ request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw GeminiError.networkTimeout
        } catch let urlError as URLError {
            throw GeminiError.networkError(urlError.localizedDescription)
        }
    }

    private func mapError(code: Int, body: Data) throws {
        switch code {
        case 200: return
        case 400:
            // Gemini returns 400 for many reasons during indexing — unsupported
            // image variants, oversized inline data, content-policy rejections.
            // Only treat as invalid-key when the body actually says so.
            if isInvalidKeyError(body) { throw GeminiError.invalidKey }
            throw GeminiError.invalidArgument
        case 401, 403: throw GeminiError.invalidKey
        case 429: throw GeminiError.rateLimited
        case 500...599: throw GeminiError.serverError
        default: throw GeminiError.unknown(code)
        }
    }

    private func isInvalidKeyError(_ body: Data) -> Bool {
        struct ErrorEnvelope: Decodable {
            struct ErrorDetail: Decodable {
                let message: String?
                let status: String?
                struct Detail: Decodable { let reason: String? }
                let details: [Detail]?
            }
            let error: ErrorDetail?
        }
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body),
              let err = envelope.error else { return false }
        if err.details?.contains(where: { $0.reason == "API_KEY_INVALID" }) == true { return true }
        if let msg = err.message, msg.localizedCaseInsensitiveContains("api key not valid") { return true }
        return false
    }

    public struct EmbedResponse: Codable, Sendable {
        public let embedding: EmbeddingValues
    }

    public struct EmbeddingValues: Codable, Sendable {
        public let values: [Float]
    }

    private struct FileUploadResponse: Codable {
        let file: FileMetadata
    }

    private struct FileMetadata: Codable {
        let name: String
        let uri: String
        let state: String?
    }

    public enum GeminiError: LocalizedError, Equatable, Sendable {
        case invalidKey
        case invalidArgument
        case rateLimited
        case networkTimeout
        case networkError(String)
        case serverError
        case unknown(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidKey:
                return "Invalid API key. Check your key in Settings."
            case .invalidArgument:
                return "Gemini rejected this item."
            case .rateLimited:
                return "Too many requests. Wait a moment and try again."
            case .networkTimeout:
                return "Request timed out. Check your internet connection."
            case .networkError(let detail):
                return "Network error: \(detail)"
            case .serverError:
                return "Gemini service is temporarily unavailable. Try again shortly."
            case .unknown(let code):
                return "Something went wrong (error \(code)). Try again."
            }
        }
    }
}
