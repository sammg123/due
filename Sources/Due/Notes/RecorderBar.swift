import SwiftUI
import DueCore

/// Live capture strip shown above the editor while a lecture records: status, elapsed time,
/// input level, and the tail of the transcript as it lands.
struct RecorderBar: View {
    @Environment(LectureEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch engine.phase {
            case .requestingMic:
                statusLine("Waiting for microphone access…")
            case .preparingModel(let status):
                statusLine(status)
            case .recording:
                recordingLine
                if !engine.liveTail.isEmpty {
                    Text(engine.liveTail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityLabel("Live transcript")
                }
            case .finishing:
                statusLine("Finishing transcription…")
            case .idle:
                EmptyView()
            }

            if let warning = engine.warning {
                HStack(spacing: 6) {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button {
                        engine.clearWarning()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange.opacity(0.8))
                    .help("Dismiss warning")
                    .accessibilityLabel("Dismiss warning")
                }
            }
        }
        .padding(.horizontal, Theme.notesEditorInset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
    }

    private func statusLine(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .opacity(pulsing ? 0.35 : 1)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulsing = true
                    }
                }
                .accessibilityHidden(true)
            Text("Recording")
                .font(.caption.weight(.semibold))
            Text(LectureEngine.elapsedText(engine.elapsed))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            LevelMeter(level: engine.level, reduceMotion: reduceMotion)
            Spacer()
            Button {
                engine.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            .help("Stop and finish the transcript")
            .accessibilityLabel("Stop recording")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording, \(LectureEngine.elapsedText(engine.elapsed)) elapsed")
    }
}

/// Tiny 12-segment input meter, tinted by how hot the signal is.
private struct LevelMeter: View {
    let level: Float
    let reduceMotion: Bool
    private static let segments = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<Self.segments, id: \.self) { i in
                Capsule()
                    .fill(color(for: i))
                    .frame(width: 3, height: 10)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }

    private func color(for index: Int) -> Color {
        let threshold = Float(index) / Float(Self.segments)
        guard level > threshold else { return Color.secondary.opacity(0.2) }
        return index >= Self.segments - 2 ? .red : .green
    }
}
