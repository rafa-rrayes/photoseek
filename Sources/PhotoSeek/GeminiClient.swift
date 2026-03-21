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

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(http.statusCode, msg)
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

    enum GeminiError: LocalizedError {
        case apiError(Int, String)

        var errorDescription: String? {
            switch self {
            case .apiError(let code, let msg): return "Gemini API error \(code): \(msg)"
            }
        }
    }
}
