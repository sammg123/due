import Foundation
import Observation
import DueCore
#if canImport(FoundationModels)
import FoundationModels
#endif

enum NoteAIAction: String, CaseIterable, Identifiable {
    case cleanUp
    case summarize
    case outline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cleanUp: return "Clean up writing"
        case .summarize: return "Summarize"
        case .outline: return "Turn into outline"
        }
    }

    var systemImage: String {
        switch self {
        case .cleanUp: return "wand.and.stars"
        case .summarize: return "text.append"
        case .outline: return "list.bullet.indent"
        }
    }

    var help: String {
        switch self {
        case .cleanUp: return "Fix grammar and structure without changing meaning"
        case .summarize: return "Add a summary section at the top"
        case .outline: return "Restructure the note as a study outline"
        }
    }
}

enum NoteAIError: LocalizedError {
    case unavailable
    case emptyNote
    case noUsableOutput

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Intelligence is unavailable on this Mac"
        case .emptyNote: return "Nothing to work with yet. Write or record something first"
        case .noUsableOutput: return "The model didn't return usable text; the note is unchanged"
        }
    }
}

/// Note transformations via Apple's on-device model (FoundationModels, macOS 26). Long notes
/// (lecture transcripts) are processed in `TextChunker` chunks because the model shares a
/// 4,096-token window between prompt and response. Same availability-gating pattern as
/// `SmartQuickAddParser`: compiles at Due's macOS 14 target, activates on 26.
@MainActor
@Observable
final class NoteAI {
    private(set) var isRunning = false
    private(set) var runningAction: NoteAIAction?

    /// Chars per model call: chunk + response must share the window (~3.5 chars/token).
    static let chunkCharacterLimit = 4_500

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return false }
        return SystemLanguageModel.default.availability == .available
        #else
        return false
        #endif
    }

    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return "Needs macOS 26" }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This Mac doesn't support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence is not enabled"
        case .unavailable(.modelNotReady): return "Apple Intelligence model is still downloading"
        case .unavailable: return "Apple Intelligence is unavailable"
        }
        #else
        return "Needs macOS 26"
        #endif
    }

    /// Returns the new body for `cleanUp`/`outline`, or the summary text for `summarize`
    /// (the caller inserts it). Never returns an empty result; it throws instead.
    func run(_ action: NoteAIAction, on body: String) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), Self.isAvailable else { throw NoteAIError.unavailable }
        let chunks = TextChunker.chunks(body, limit: Self.chunkCharacterLimit)
        guard !chunks.isEmpty else { throw NoteAIError.emptyNote }
        isRunning = true
        runningAction = action
        defer {
            isRunning = false
            runningAction = nil
        }
        switch action {
        case .cleanUp:
            return try await rewrite(chunks, instructions: Self.cleanUpInstructions, fallbackToOriginal: true)
        case .outline:
            return try await rewrite(chunks, instructions: Self.outlineInstructions, fallbackToOriginal: false)
        case .summarize:
            return try await summarize(chunks)
        }
        #else
        throw NoteAIError.unavailable
        #endif
    }
}

#if canImport(FoundationModels)

@available(macOS 26, *)
extension NoteAI {
    // Permissive guardrails: designed for exactly this kind of text-to-text transformation
    // (same configuration LocalFlow's polisher uses). Nonisolated so the timeout-raced
    // model call can construct its session off the main actor.
    private nonisolated static var model: SystemLanguageModel {
        SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }

    private static let cleanUpInstructions = Instructions("""
        You clean up a student's rough class notes. Fix grammar, punctuation, casing, and
        run-on transcription into readable sentences and short paragraphs. Keep the student's
        meaning, wording style, and every fact exactly as written. Never add information,
        never drop a point, never editorialize. Keep any lines starting with '#' unchanged.
        Reply with ONLY the cleaned text, no preamble.
        """)

    private static let outlineInstructions = Instructions("""
        You turn a student's class notes into a structured study outline. Use short '##'
        headings for topics and '-' bullets for points, nesting with two spaces where it
        helps. Keep every fact from the notes and add none. Reply with ONLY the outline,
        no preamble.
        """)

    private static let summarizeInstructions = Instructions("""
        You summarize a student's class notes. Reply with ONLY 3 to 6 '-' bullets capturing
        the key ideas, definitions, and takeaways, no preamble.
        """)

    private static let combineInstructions = Instructions("""
        You merge several partial summaries of one lecture into a single summary. Reply with
        ONLY at most 8 '-' bullets, deduplicated, no preamble.
        """)

    /// One model call per chunk. `fallbackToOriginal` keeps a chunk untouched when the model
    /// returns junk (clean-up must never lose content); outline chunks fail hard instead.
    fileprivate func rewrite(_ chunks: [String], instructions: Instructions, fallbackToOriginal: Bool) async throws -> String {
        var pieces: [String] = []
        for chunk in chunks {
            if let output = await Self.respond(instructions: instructions, prompt: chunk),
               Self.plausible(output: output, input: chunk) {
                pieces.append(output)
            } else if fallbackToOriginal {
                pieces.append(chunk)
            } else {
                throw NoteAIError.noUsableOutput
            }
        }
        return pieces.joined(separator: "\n\n")
    }

    fileprivate func summarize(_ chunks: [String]) async throws -> String {
        var partials: [String] = []
        for chunk in chunks {
            if let output = await Self.respond(instructions: Self.summarizeInstructions, prompt: chunk),
               !output.isEmpty {
                partials.append(output)
            }
        }
        guard !partials.isEmpty else { throw NoteAIError.noUsableOutput }
        guard partials.count > 1 else { return partials[0] }
        let combined = partials.joined(separator: "\n")
        guard let merged = await Self.respond(instructions: Self.combineInstructions, prompt: combined),
              !merged.isEmpty
        else { return combined }
        return merged
    }

    /// Per-chunk model call. A FRESH session every time is deliberate: a session's 4,096-token
    /// window spans its whole transcript, so reusing one across chunks would overflow on long
    /// notes (same reason LocalFlow's polisher makes a session per dictation). The timeout keeps
    /// a hung model call from leaving `isRunning` stuck forever.
    private static func respond(instructions: Instructions, prompt: String) async -> String? {
        let options = GenerationOptions(
            sampling: .greedy, // deterministic transformation
            maximumResponseTokens: max(512, prompt.count / 2)
        )
        do {
            return try await withTimeout(seconds: 60) {
                let session = LanguageModelSession(model: model, instructions: instructions)
                let response = try await session.respond(to: prompt, options: options)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            NSLog("Due: note AI call failed: \(error.localizedDescription)")
            return nil
        }
    }

    private struct TimedOut: Error {}

    /// Races `operation` against a timeout; the loser is abandoned. Same shape as the
    /// quick-add parser's guard, scoped here because that one is file-private.
    private static func withTimeout<T: Sendable>(
        seconds: Double, operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw TimedOut() }
            return result
        }
    }

    /// Refusals come back AS the string with permissive guardrails; length-gate the rest.
    private static func plausible(output: String, input: String) -> Bool {
        guard !output.isEmpty else { return false }
        let lowered = output.lowercased()
        for refusal in ["i can't", "i cannot", "i'm sorry", "i am sorry", "i'm unable"] where lowered.hasPrefix(refusal) {
            return false
        }
        let ratio = Double(output.count) / Double(max(input.count, 1))
        return ratio > 0.3 && ratio < 3.5
    }
}

#endif
