import Foundation

/// Minimal client for a local Ollama server (loopback only; nothing leaves the Mac).
/// Used by the notes AI when a stronger local model than Apple's is available.
enum OllamaClient {
    static let baseURL = URL(string: "http://127.0.0.1:11434")!
    /// Big models can take ~10s to load into RAM on first use, then a few seconds per call.
    static let chatTimeout: TimeInterval = 180
    static let probeTimeout: TimeInterval = 2

    enum OllamaError: LocalizedError {
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let detail): return "Ollama request failed: \(detail)"
            }
        }
    }

    /// Installed model names, or nil when no Ollama server is running.
    static func installedModels() async -> [String]? {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"), timeoutInterval: probeTimeout)
        request.httpMethod = "GET"
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let parsed = try? JSONDecoder().decode(TagsResponse.self, from: data)
        else { return nil }
        return parsed.models.map(\.name)
    }

    /// One non-streaming chat completion. Thinking is disabled and any leaked reasoning
    /// stripped: some models narrate their chain of thought into the answer otherwise.
    /// `images` (PNG data) go to multimodal models only; text models would ignore them.
    static func chat(model: String, system: String, prompt: String, images: [Data] = []) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"), timeoutInterval: chatTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: model,
            messages: [
                Message(role: "system", content: system),
                Message(role: "user", content: prompt, images: images.isEmpty ? nil : images.map { $0.base64EncodedString() }),
            ]
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = String(data: data.prefix(200), encoding: .utf8) ?? "status \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            throw OllamaError.badResponse(detail)
        }
        let parsed = try JSONDecoder().decode(ChatResponse.self, from: data)
        return sanitize(parsed.message.content)
    }

    /// Drops `<think>…</think>` blocks and any long reasoning preamble before the first
    /// heading, so a leaky model still yields renderable notes.
    static func sanitize(_ raw: String) -> String {
        var text = raw
        if let closing = text.range(of: "</think>", options: .backwards) {
            text = String(text[closing.upperBound...])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.hasPrefix("#"), !text.hasPrefix("-"),
           let heading = text.range(of: "\n## "),
           text.distance(from: text.startIndex, to: heading.lowerBound) > 200 {
            text = String(text[text.index(after: heading.lowerBound)...])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Wire types

    private struct TagsResponse: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }

    private struct Message: Codable {
        let role: String
        let content: String
        var images: [String]?

        init(role: String, content: String, images: [String]? = nil) {
            self.role = role
            self.content = content
            self.images = images
        }
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream = false
        let think = false
        let options = Options()

        struct Options: Encodable {
            // Ollama defaults num_ctx to 4096; whole-note instruction edits need real room.
            let num_ctx = 32_768
            let temperature = 0.0
        }
    }

    private struct ChatResponse: Decodable {
        let message: Message
    }
}
