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

    /// Families known to accept images. No generic fallback: most models are text-only and
    /// would silently ignore the image, so nil means "no vision available".
    static let visionRanking = ["gemma4", "gemma3", "qwen3-vl", "qwen2.5vl", "llava", "llama3.2-vision", "minicpm-v"]

    public static func preferredVision(from installed: [String]) -> String? {
        visionCandidates(from: installed).first
    }

    /// All vision-family matches in preference order. Callers try them in turn: a specific
    /// build can lack image support even when its family has it (measured: a gemma4 mlx
    /// build rejects images while gemma3 accepts them).
    public static func visionCandidates(from installed: [String]) -> [String] {
        let candidates = installed.filter { !$0.localizedCaseInsensitiveContains("embed") }
        return visionRanking.flatMap { family in
            candidates.filter { $0.hasPrefix(family) }
        }
    }
}
