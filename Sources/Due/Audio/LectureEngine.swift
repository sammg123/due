import AppKit
import AVFoundation
import FluidAudio
import Foundation
import Observation
import DueCore

/// Lecture capture: mic → Parakeet (CoreML on the Neural Engine, via FluidAudio) → transcript
/// chunks appended to the note, with the raw audio optionally saved as .m4a beside the notes.
///
/// Lives at the app level (not the window) so closing the notes window never kills a recording.
/// Chunks are cut at pauses (`AudioChunk.cutPoint`) and the TDT decoder state carries across
/// chunks of one session, so words don't garble at chunk boundaries.
///
/// The Parakeet model (~483 MB, one-time download) is cached in the FluidAudio directory
/// shared with LocalFlow, so a Mac with LocalFlow already has it.
@MainActor
@Observable
final class LectureEngine {
    enum Phase: Equatable {
        case idle
        case requestingMic
        case preparingModel(String)
        case recording
        case finishing
    }

    private(set) var phase: Phase = .idle
    private(set) var noteID: UUID?
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    /// Tail of the transcript so far, for the live preview line in the recorder bar.
    private(set) var liveTail: String = ""
    /// Non-fatal problems (a failed chunk, a lost input device). Recording continues when it can.
    private(set) var warning: String?

    private let recorder = AudioRecorder()
    private var asr: AsrManager?
    /// Shared so a cancel-then-retry during the one-time download reuses the same load.
    private var modelLoad: Task<AsrManager, Error>?
    private var decoderState: TdtDecoderState?
    private var notesState: NotesState?
    private var audioFile: AVAudioFile?
    private var audioFileName: String?
    private var carry: [Float] = []
    private var tickTask: Task<Void, Never>?
    private var isProcessingChunk = false
    private var cancelRequested = false
    private var sessionHeading = ""
    /// Set once in init, removed in deinit; nonisolated(unsafe) only so deinit can reach it.
    private nonisolated(unsafe) var terminationObserver: NSObjectProtocol?

    /// Transcribe roughly every 30s of speech; look for a pause in the last 5s to cut at.
    private static let chunkTargetSeconds = 30
    private static let cutSearchSeconds = 5
    private static let sampleRate = Int(AudioRecorder.targetSampleRate)
    /// Parakeet rejects audio under 300 ms; shorter leftovers are padded or dropped.
    private static let minChunkSamples = Int(0.3 * AudioRecorder.targetSampleRate)

    init() {
        // Quitting mid-lecture must not truncate the .m4a or drop the note's recording entry.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleTermination() }
        }
    }

    var isActive: Bool { phase != .idle }
    var isRecording: Bool { phase == .recording }

    private var isPreparingModel: Bool {
        if case .preparingModel = phase { return true }
        return false
    }

    func isCapturing(_ id: UUID?) -> Bool { isActive && noteID == id }

    func clearWarning() { warning = nil }

    // MARK: - Session lifecycle

    func start(noteID: UUID, notesState: NotesState, saveAudio: Bool) async {
        guard phase == .idle else { return }
        warning = nil
        liveTail = ""
        elapsed = 0
        carry = []
        self.noteID = noteID
        self.notesState = notesState

        cancelRequested = false
        phase = .requestingMic
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard !cancelRequested else {
            cancelRequested = false
            return
        }
        guard granted else {
            fail("Microphone access is off. Enable it in System Settings → Privacy & Security → Microphone.")
            return
        }

        do {
            try await prepareModel()
        } catch {
            guard !cancelRequested else {
                cancelRequested = false
                return
            }
            fail("Could not load the speech model: \(error.localizedDescription)")
            return
        }
        guard !cancelRequested else {
            cancelRequested = false
            return
        }

        sessionHeading = "Lecture · \(Self.headingFormatter.string(from: Date()))"
        if saveAudio { openAudioFile(noteID: noteID) }

        recorder.levelHandler = { [weak self] level in
            DispatchQueue.main.async { self?.level = level }
        }
        recorder.captureLostHandler = { [weak self] in
            self?.warning = "Audio input was lost (device changed). Recording stopped."
            self?.stop()
        }
        recorder.overflowHandler = { [weak self] in
            self?.warning = "Transcription fell too far behind. Recording stopped."
            self?.stop()
        }

        do {
            try recorder.start()
        } catch {
            fail("Could not start the microphone: \(error.localizedDescription)")
            return
        }
        phase = .recording
        startTicking()
    }

    func stop() {
        // During mic-request or the model download there is nothing recorded yet: just bail out.
        // start() checks `cancelRequested` after each await and unwinds without side effects.
        if phase == .requestingMic || isPreparingModel {
            cancelRequested = true
            noteID = nil
            notesState = nil
            phase = .idle
            return
        }
        guard phase == .recording else { return }
        phase = .finishing
        // Mic off immediately; `rest` holds everything since the last drain.
        let rest = recorder.stop()
        let seconds = Int(recorder.capturedDuration.rounded())
        // Not cancelled: the tick loop exits on its own phase guard (≤0.5s), and waiting for
        // it means an in-flight chunk finishes transcribing before the final one starts.
        // Cancelling could abort a transcription mid-chunk and lose its words.
        let tick = tickTask
        tickTask = nil
        Task {
            _ = await tick?.value
            await self.processChunk(rest, isFinal: true)
            self.finishSession(seconds: seconds)
        }
    }

    private func finishSession(seconds: Int) {
        audioFile = nil // closes the file
        if let noteID, let audioFileName {
            notesState?.recordAudioFile(noteID, fileName: audioFileName, seconds: seconds)
        }
        audioFileName = nil
        decoderState = nil
        notesState = nil
        noteID = nil
        level = 0
        phase = .idle
    }

    private func fail(_ message: String) {
        warning = message
        noteID = nil
        notesState = nil
        phase = .idle
    }

    /// App is quitting mid-lecture: get the audio on disk and the recording onto the note,
    /// synchronously. The un-transcribed tail can't run through the model here (async), but
    /// the .m4a keeps every sample so nothing is unrecoverable.
    private func handleTermination() {
        guard phase == .recording || phase == .finishing else { return }
        let rest = recorder.stop()
        writeAudio(rest)
        let seconds = Int(recorder.capturedDuration.rounded())
        audioFile = nil // closes the file so the .m4a isn't truncated
        if let noteID, let audioFileName {
            notesState?.recordAudioFile(noteID, fileName: audioFileName, seconds: seconds)
        }
        notesState?.flushPendingSaves()
        phase = .idle
    }

    // MARK: - Model

    private func prepareModel() async throws {
        guard asr == nil else { return }
        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
        let downloaded = AsrModels.modelsExist(at: cacheDir, version: .v3, encoderPrecision: .int8)
        phase = .preparingModel(downloaded ? "Loading speech model…" : "Downloading speech model (one-time, ~500 MB)…")
        // One shared load task: cancel-then-retry during the download reuses it instead of
        // kicking off a second concurrent download.
        let load: Task<AsrManager, Error>
        if let modelLoad {
            load = modelLoad
        } else {
            load = Task {
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                return AsrManager(config: .default, models: models)
            }
            modelLoad = load
        }
        do {
            asr = try await load.value
        } catch {
            modelLoad = nil
            throw error
        }
    }

    // MARK: - Chunk loop

    private func startTicking() {
        tickTask = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, self.phase == .recording else { return }
                self.elapsed = self.recorder.capturedDuration
                let buffered = self.recorder.bufferedSampleCount
                if !self.isProcessingChunk, buffered >= Self.chunkTargetSeconds * Self.sampleRate {
                    await self.processChunk(self.recorder.drain(), isFinal: false)
                }
            }
        }
    }

    /// Appends audio to the m4a, transcribes up to a pause, and appends the text to the note.
    /// `carry` holds the samples after the cut so the next chunk starts mid-pause, not mid-word.
    private func processChunk(_ drained: [Float], isFinal: Bool) async {
        // Every drained sample hits the .m4a exactly once, in arrival order, regardless of the
        // carry/cut bookkeeping below (which exists only for transcription continuity). Writing
        // `carry + drained` here instead would re-write the carried tail at every boundary.
        writeAudio(drained)

        guard !isProcessingChunk else {
            carry.append(contentsOf: drained)
            return
        }
        isProcessingChunk = true
        defer { isProcessingChunk = false }

        let samples = carry + drained
        carry = []
        guard !samples.isEmpty else { return }

        let cut = isFinal
            ? samples.count
            : AudioChunk.cutPoint(samples: samples, sampleRate: Self.sampleRate, searchWindowSeconds: Self.cutSearchSeconds)
        let chunk = Array(samples[..<cut])
        carry = Array(samples[cut...])

        // Below Parakeet's floor and nothing more coming: drop the (silence-length) leftover.
        guard chunk.count >= Self.minChunkSamples || !isFinal else { return }
        guard let asr, let noteID else { return }

        do {
            var padded = chunk
            if padded.count < Self.minChunkSamples {
                padded.append(contentsOf: [Float](repeating: 0, count: Self.minChunkSamples - padded.count))
            }
            // Decoder state carries across this session's chunks (it's one continuous stream);
            // a fresh session starts from a fresh state.
            var state: TdtDecoderState
            if let existing = decoderState {
                state = existing
            } else {
                state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
            }
            let result = try await asr.transcribe(padded, decoderState: &state)
            decoderState = state
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            notesState?.appendTranscript(noteID, text: text, sessionHeading: sessionHeading)
            liveTail = String((liveTail + " " + text).suffix(160)).trimmingCharacters(in: .whitespaces)
        } catch {
            NSLog("Due: lecture chunk transcription failed: \(error.localizedDescription)")
            warning = "A transcription chunk failed; audio capture continues."
        }
    }

    // MARK: - Audio file

    private func openAudioFile(noteID: UUID) {
        guard let dir = notesState?.audioDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = "\(noteID.uuidString)-\(Self.fileFormatter.string(from: Date())).m4a"
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: AudioRecorder.targetSampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            audioFile = try AVAudioFile(
                forWriting: dir.appendingPathComponent(name),
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            audioFileName = name
        } catch {
            NSLog("Due: could not create recording file: \(error.localizedDescription)")
            warning = "Audio can't be saved (\(error.localizedDescription)); transcription continues."
            audioFile = nil
            audioFileName = nil
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    private func writeAudio(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        guard let audioFile,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: AudioRecorder.targetSampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            channel.update(from: src.baseAddress!, count: samples.count)
        }
        do {
            try audioFile.write(from: buffer)
        } catch {
            NSLog("Due: audio write failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Formatting

    private static let headingFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    private static let fileFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    static func elapsedText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
