import Foundation

/// Picks which installed Ollama model the notes AI should use when set to "auto".
/// Pure ranking over model names; the network call that lists them lives in the app target.
public enum OllamaModels {
    /// Families in preference order. Bare "qwen3" ranks below the gemmas deliberately:
    /// those builds leak chain-of-thought into their output even with thinking disabled.
    static let familyRanking = ["qwen3.6", "gemma4", "gemma3", "llama", "mistral", "qwen3"]

    public static func preferred(from installed: [String]) -> String? {
        let candidates = installed.filter { !$0.localizedCaseInsensitiveContains("embed") }
        for family in familyRanking {
            if let match = candidates.first(where: { $0.hasPrefix(family) }) { return match }
        }
        return candidates.first
    }
}
