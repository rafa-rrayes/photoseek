import Foundation

actor GeminiClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func embedText(_ text: String, apiKey: String) async throws -> [Float] {
        let body: [String: Any] = [
            "content": ["parts": [["text": text]]],
            "taskType": "RETRIEVAL_QUERY",
            "output_dimensionality": 768
        ]
        return try await callEmbed(body: body, apiKey: apiKey)
    }

    func embedImage(_ jpegData: Data, apiKey: String) async throws -> [Float] {
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
        return try await callEmbed(body: body, apiKey: apiKey)
    }

    private func callEmbed(body: [String: Any], apiKey: String) async throws -> [Float] {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-2-preview:embedContent")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw GeminiError.networkTimeout
        } catch let urlError as URLError {
            throw GeminiError.networkError(urlError.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            switch http.statusCode {
            case 400, 403:
                throw GeminiError.invalidKey
            case 429:
                throw GeminiError.rateLimited
            case 500...599:
                throw GeminiError.serverError
            default:
                throw GeminiError.unknown(http.statusCode)
            }
        }

        let result = try JSONDecoder().decode(EmbedResponse.self, from: data)
        return result.embedding.values
    }

    struct EmbedResponse: Codable {
        let embedding: EmbeddingValues
    }

    struct EmbeddingValues: Codable {
        let values: [Float]
    }

    enum GeminiError: LocalizedError, Equatable {
        case invalidKey
        case rateLimited
        case networkTimeout
        case networkError(String)
        case serverError
        case unknown(Int)

        var errorDescription: String? {
            switch self {
            case .invalidKey:
                return "Invalid API key. Check your key in Settings."
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
