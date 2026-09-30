import Foundation

enum CorrectionError: LocalizedError {
    case invalidResponse
    case emptyResponse
    case rateLimited
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "OpenRouter returned an unreadable response."
        case .emptyResponse: return "The model returned no corrected text."
        case .rateLimited: return "OpenRouter’s providers are rate-limiting requests right now. Try again in a moment, or choose another model."
        case .server(let message): return message
        }
    }
}

struct OpenRouterClient {
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    static let instruction = """
        Return only the corrected text, without a preface, quotes, or a code block. Correct spelling mistakes and incorrect or missing accents in French or English. Preserve every other word choice, grammar, punctuation, capitalization, line break, whitespace character, Markdown marker, URL, and code span exactly. Do not rewrite or improve the text. If there are no spelling mistakes, return the input exactly.
        """

    /// Returns the corrected text and the model that produced it.
    func correct(_ text: String, apiKey: String, model: String) async throws -> (text: String, model: String) {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            // When the model's providers are rate-limited or down, OpenRouter tries the next model in order.
            "models": Self.fallbackChain(for: model),
            "temperature": 0,
            "provider": ["sort": "latency"],
            "messages": [
                ["role": "system", "content": Self.instruction],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CorrectionError.invalidResponse }
        if http.statusCode == 429 { throw CorrectionError.rateLimited }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            let detail = apiError?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw CorrectionError.server("OpenRouter (\(http.statusCode)): \(detail)")
        }
        guard let completion = try? JSONDecoder().decode(Completion.self, from: data),
              let content = completion.choices.first?.message.content else {
            throw CorrectionError.invalidResponse
        }
        guard !content.isEmpty else { throw CorrectionError.emptyResponse }
        return (content, completion.model ?? model)
    }

    /// The chosen model first, then two presets as fallbacks.
    static func fallbackChain(for model: String) -> [String] {
        Array(([model] + ModelCatalog.presets.compactMap(\.id).filter { $0 != model }).prefix(3))
    }
}

private struct Completion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
    let model: String?
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}
