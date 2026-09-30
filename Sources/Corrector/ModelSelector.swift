import Foundation

actor ModelSelector {
    static let shared = ModelSelector()

    // These general-purpose models handle French and English text. Restricting
    // the live latency ranking avoids selecting safety, code, or tiny models.
    private let candidates: Set<String> = [
        "deepseek/deepseek-v4.1-flash",
        "mistralai/mistral-small-2603",
        "google/gemini-3.5-flash-lite",
        "google/gemini-2.5-flash-lite",
        "google/gemini-3.1-flash-lite",
        "openai/gpt-6-luna"
    ]
    private var cached: (model: String, until: Date)?

    func fastestAvailable() async -> String {
        if let cached, cached.until > Date() { return cached.model }
        guard let url = URL(string: "https://openrouter.ai/api/v1/models?sort=latency-low-to-high&input_modalities=text&output_modalities=text") else {
            return "openrouter/auto"
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return "openrouter/auto" }
            let catalog = try JSONDecoder().decode(OpenRouterModelList.self, from: data)
            guard let model = catalog.data.first(where: { candidates.contains($0.id) })?.id else {
                return "openrouter/auto"
            }
            cached = (model, Date().addingTimeInterval(30 * 60))
            return model
        } catch {
            return "openrouter/auto"
        }
    }
}

private struct OpenRouterModelList: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}
