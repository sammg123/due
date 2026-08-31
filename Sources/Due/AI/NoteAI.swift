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
        case .cleanUp: return "Fix up & format"
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
        case .cleanUp: return "Restructure into clean formatted notes, keeping every fact"
        case .summarize: return "Add a summary section at the top"
        case .outline: return "Restructure the note as a study outline"
        }
    }
}

enum NoteAIError: LocalizedError {
    case noEngine
    case emptyNote
    case noUsableOutput
    case noteTooLong

    var errorDescription: String? {
        switch self {
        case .noEngine: return "No AI model available. Enable Apple Intelligence or start Ollama"
        case .emptyNote: return "Nothing to work with yet. Write or record something first"
        case .noUsableOutput: return "The model didn't return usable text; the note is unchanged"
        case .noteTooLong: return "This note is too long for instruction edits. Run Fix up or Outline first"
        }
    }
}

/// Which local model runs a notes AI action. Resolved per run from the setting:
/// an Ollama model when one is installed and running (stronger, bigger context),
/// else Apple's on-device model (macOS 26). Both are fully local.
enum NoteAIEngine {
    case apple
    case ollama(model: String)

    /// Chars per model call. Apple's model shares a 4,096-token window between prompt and
    /// response; Ollama runs with a 16k context, so chunks can be much larger.
    var chunkCharacterLimit: Int {
        switch self {
        case .apple: return 4_500
        case .ollama: return 12_000
        }
    }

    var shortName: String {
        switch self {
        case .apple: return "Apple Intelligence"
        case .ollama(let model): return String(model.split(separator: ":").first ?? Substring(model))
        }
    }
}

/// Note transformations on a local model, chunked via `TextChunker` for long notes
/// (lecture transcripts). The FoundationModels path uses the same availability-gating
/// pattern as `SmartQuickAddParser`: compiles at Due's macOS 14 target, activates on 26.
@MainActor
@Observable
final class NoteAI {
    private(set) var isRunning = false
    /// What the status bar shows while running: an action label or "Editing".
    private(set) var runningLabel: String?
    /// Short model name while running, for the status bar.
    private(set) var engineName: String?
    /// Whether a local Ollama server with at least one model answered the last probe.
    private(set) var ollamaAvailable = false

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

    var canRun: Bool { Self.isAvailable || ollamaAvailable }

    func refreshAvailability() async {
        ollamaAvailable = await OllamaClient.installedModels()?.isEmpty == false
    }

    /// Maps the settings value ("auto" / "apple" / an Ollama model name) onto a live engine.
    /// "auto" prefers the best installed Ollama model: stronger and, unlike Apple's model,
    /// it doesn't refuse symbol-dense notes as an "unsupported language".
    static func resolveEngine(setting: String) async throws -> NoteAIEngine {
        switch setting {
        case DueSettings.appleAIModel:
            guard isAvailable else { throw NoteAIError.noEngine }
            return .apple
        case DueSettings.autoAIModel:
            if let installed = await OllamaClient.installedModels(),
               let pick = OllamaModels.preferred(from: installed) {
                return .ollama(model: pick)
            }
            guard isAvailable else { throw NoteAIError.noEngine }
            return .apple
        default:
            return .ollama(model: setting)
        }
    }

    /// Returns the new body for `cleanUp`/`outline`, or the summary text for `summarize`
    /// (the caller inserts it). Never returns an empty result; it throws instead.
    func run(_ action: NoteAIAction, on body: String, modelSetting: String) async throws -> String {
        isRunning = true
        runningLabel = action.label
        // engineName deliberately survives the run (it names the last engine used).
        defer {
            isRunning = false
            runningLabel = nil
        }
        let engine = try await Self.resolveEngine(setting: modelSetting)
        engineName = engine.shortName
        let chunks = TextChunker.chunks(body, limit: engine.chunkCharacterLimit)
        guard !chunks.isEmpty else { throw NoteAIError.emptyNote }
        switch action {
        case .cleanUp:
            return try await rewrite(chunks, engine: engine, instructions: Self.cleanUpText, fallbackToOriginal: true)
        case .outline:
            return try await rewrite(chunks, engine: engine, instructions: Self.outlineText, fallbackToOriginal: false)
        case .summarize:
            return try await summarize(chunks, engine: engine)
        }
    }

    /// Free-form instruction edit ("turn the key terms into a table", "make flashcards").
    /// Applied to the whole note in ONE model call: a global instruction chunked per-piece
    /// would run once per chunk, so overlong notes error instead. An empty note is allowed;
    /// instructions like "write a template for chem lecture notes" generate from scratch.
    func runCustom(_ instruction: String, on body: String, modelSetting: String) async throws -> String {
        isRunning = true
        runningLabel = "Editing"
        defer {
            isRunning = false
            runningLabel = nil
        }
        let engine = try await Self.resolveEngine(setting: modelSetting)
        engineName = engine.shortName
        guard body.count <= engine.chunkCharacterLimit else { throw NoteAIError.noteTooLong }
        let noteSection = body.isEmpty ? "Their note is currently empty." : "Their note:\n\(body)"
        let prompt = "Instruction from the student: \(instruction)\n\n\(noteSection)"
        guard let output = await respond(engine: engine, instructions: Self.customEditText, prompt: prompt),
              Self.usable(output)
        else { throw NoteAIError.noUsableOutput }
        return output
    }

    // MARK: - Chunk loops

    /// One model call per chunk. `fallbackToOriginal` keeps a chunk untouched when the model
    /// returns junk (fix-up must never lose content); outline chunks fail hard instead.
    /// No length-ratio gate here: outlines legitimately compress notes hard, and fix-up
    /// legitimately expands them into structure. Only refusals/empties are junk.
    private func rewrite(_ chunks: [String], engine: NoteAIEngine, instructions: String, fallbackToOriginal: Bool) async throws -> String {
        var pieces: [String] = []
        for chunk in chunks {
            if let output = await respond(engine: engine, instructions: instructions, prompt: chunk),
               Self.usable(output) {
                pieces.append(output)
            } else if fallbackToOriginal {
                pieces.append(chunk)
            } else {
                throw NoteAIError.noUsableOutput
            }
        }
        return pieces.joined(separator: "\n\n")
    }

    private func summarize(_ chunks: [String], engine: NoteAIEngine) async throws -> String {
        var partials: [String] = []
        for chunk in chunks {
            if let output = await respond(engine: engine, instructions: Self.summarizeText, prompt: chunk),
               Self.usable(output) {
                partials.append(output)
            }
        }
        guard !partials.isEmpty else { throw NoteAIError.noUsableOutput }
        guard partials.count > 1 else { return partials[0] }
        let combined = partials.joined(separator: "\n")
        guard let merged = await respond(engine: engine, instructions: Self.combineText, prompt: combined),
              Self.usable(merged)
        else { return combined }
        return merged
    }

    private func respond(engine: NoteAIEngine, instructions: String, prompt: String) async -> String? {
        switch engine {
        case .ollama(let model):
            do {
                return try await OllamaClient.chat(model: model, system: instructions, prompt: prompt)
            } catch {
                NSLog("Due: Ollama call failed (\(model)): \(String(describing: error))")
                return nil
            }
        case .apple:
            #if canImport(FoundationModels)
            guard #available(macOS 26, *) else { return nil }
            return await Self.appleRespond(instructions: instructions, prompt: prompt)
            #else
            return nil
            #endif
        }
    }

    /// Refusals come back AS the string with permissive guardrails; that (and empty) is the
    /// only junk worth rejecting. Length ratios are NOT checked: a valid outline can be a
    /// fifth of the input and a valid fix-up double it.
    private static func usable(_ output: String) -> Bool {
        guard !output.isEmpty else { return false }
        let lowered = output.lowercased()
        for refusal in ["i can't", "i cannot", "i'm sorry", "i am sorry", "i'm unable"] where lowered.hasPrefix(refusal) {
            return false
        }
        return true
    }

    // MARK: - Instructions (shared by both engines)

    /// The markdown dialect Due's reading view renders. Shared by every action so the model
    /// output always lands renderable.
    private static let formatSpec = """
        Formatting rules for your reply (Due renders these):
        - '## ' for topic headings, '### ' for sub-headings.
        - '- ' bullets, nested with two leading spaces per level; '1. ' for ordered steps.
        - **bold** ONLY the term a line defines (one or two bolds per line at most); \
        *italics* for emphasis; `code` for formulas and symbols.
        - '> ' for one-line callouts (definitions worth remembering, exam warnings).
        - A markdown table (| a | b | rows) when the notes compare things.
        - When the notes describe a step-by-step process, put it on ONE plain lowercase \
        line joined by arrows, for example: flow: sort the data -> compute quartiles -> \
        compute fences -> flag outliers. Never make this a heading.
        - '---' alone on a line to separate major sections.
        Never use LaTeX or $...$ math; write formulas in `code` backticks.
        Reply with ONLY the formatted notes, no preamble.
        """

    private static let cleanUpText = """
        You fix up a student's rough class notes: correct grammar, punctuation, and
        transcription run-ons, then reorganize into clean structure with headings, bullets,
        and bold key terms. Keep the student's meaning and EVERY fact exactly as written.
        Never add information, never drop a point, never editorialize.

        \(formatSpec)

        Example: "iqr = q3-q1 measures spread of middle 50. to find outliers sort data then \
        get fences then flag whats outside" becomes:
        ## Interquartile Range
        - **IQR** = `Q3 - Q1`: measures how spread out the middle 50% is.

        flow: sort the data -> compute the fences -> flag values outside
        """

    private static let outlineText = """
        You turn a student's class notes into a structured study outline: '##' headings per
        topic, nested bullets for the points under each, key terms bolded. Keep every fact
        from the notes and add none. An outline is allowed to be much shorter than the notes.

        \(formatSpec)
        """

    private static let summarizeText = """
        You summarize a student's class notes into 3 to 6 bullets capturing the key ideas,
        definitions, and takeaways. Start each bullet with the **bolded** concept it covers.
        Add nothing the notes don't say.

        \(formatSpec)
        """

    private static let combineText = """
        You merge several partial summaries of one lecture into a single deduplicated
        summary of at most 8 bullets, each starting with its **bolded** concept.

        \(formatSpec)
        """

    private static let customEditText = """
        You edit a student's class notes exactly as their instruction asks: rewrite,
        restructure, add, remove, or transform as requested. Your reply REPLACES the whole
        note, so include everything that should remain. Unless the instruction says
        otherwise, keep every existing fact.

        \(formatSpec)
        """
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

    /// Per-chunk model call. A FRESH session every time is deliberate: a session's 4,096-token
    /// window spans its whole transcript, so reusing one across chunks would overflow on long
    /// notes (same reason LocalFlow's polisher makes a session per dictation). The timeout keeps
    /// a hung model call from leaving `isRunning` stuck forever.
    fileprivate static func appleRespond(instructions instructionsText: String, prompt: String) async -> String? {
        // TOKENS, not characters (~3.5 chars/token): fix-up expands notes into structure,
        // so budget a bit over the input's own token count. A near-limit 4,500-char chunk
        // is ~1,300 prompt tokens + ~1,500 response tokens, safely inside the 4,096 window.
        let options = GenerationOptions(
            sampling: .greedy, // deterministic transformation
            maximumResponseTokens: max(1024, prompt.count / 3)
        )
        do {
            return try await withTimeout(seconds: 60) {
                let session = LanguageModelSession(model: model, instructions: Instructions(instructionsText))
                let response = try await session.respond(to: prompt, options: options)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // Full error, not just localizedDescription: FoundationModels errors carry the
            // useful detail (guardrail case, context size, language rejection) in the payload.
            NSLog("Due: note AI call failed: \(String(describing: error))")
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
}

#endif
