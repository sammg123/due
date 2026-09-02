import SwiftUI
import DueCore

/// Formatted, read-only rendering of a note's markdown: styled headings, bullets, callouts,
/// tables, and `flow:` step diagrams, tinted with the note's course color. Clicking anywhere
/// hands back to the editor.
struct NoteReadingView: View {
    @Environment(NotesState.self) private var notes
    let text: String
    let accent: Color
    let onEdit: () -> Void
    let onEditDrawing: (UUID) -> Void

    /// Parsed once per body change, not per render pass: any keystroke elsewhere (the title
    /// field, say) re-renders this view, and re-parsing a lecture-length body each time is
    /// avoidable main-thread work.
    @State private var blocks: [NoteBlock] = []

    var body: some View {
        ScrollView {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Nothing here yet. Click to start writing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .padding(.horizontal, Theme.notesEditorInset)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: text) { blocks = NoteMarkdown.blocks(text) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Click to edit the note")
    }

    // MARK: - Blocks

    @ViewBuilder
    private func blockView(_ block: NoteBlock) -> some View {
        switch block {
        case .heading(let level, let runs):
            heading(level: level, runs: runs)
        case .bullet(let indent, let runs):
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(accent.opacity(0.85))
                    .frame(width: 5, height: 5)
                    .padding(.top, 7)
                inlineText(runs)
            }
            .padding(.leading, CGFloat(indent) * 18)
        case .numbered(let number, let indent, let runs):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(number).")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                inlineText(runs)
            }
            .padding(.leading, CGFloat(indent) * 18)
        case .paragraph(let indent, let runs):
            inlineText(runs)
                .padding(.leading, CGFloat(indent) * 18)
        case .callout(let runs):
            HStack(alignment: .top, spacing: 9) {
                Capsule()
                    .fill(accent)
                    .frame(width: 3)
                inlineText(runs)
                    .padding(.vertical, 1)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius))
            .padding(.vertical, 2)
        case .divider:
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
                .padding(.vertical, 6)
        case .table(let header, let rows):
            table(header: header, rows: rows)
        case .flow(let steps):
            flow(steps)
        case .drawing(let id):
            if let drawing = notes.drawing(id) {
                DrawingBlockView(drawing: drawing)
                    .onTapGesture { onEditDrawing(id) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Click to edit the drawing")
            } else {
                Text("Missing drawing")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func heading(level: Int, runs: [NoteInlineRun]) -> some View {
        let font: Font = switch level {
        case 1: .system(size: 21, weight: .bold)
        case 2: .system(size: 16, weight: .semibold)
        default: .system(size: 14, weight: .semibold)
        }
        return VStack(alignment: .leading, spacing: 4) {
            inlineText(runs, font: font)
            if level <= 2 {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accent.opacity(0.75))
                    .frame(width: level == 1 ? 40 : 26, height: 3)
            }
        }
        .padding(.top, level == 1 ? 10 : 8)
    }

    private func table(header: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                    Text(cell)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        inlineText(NoteMarkdown.runs(cell), font: .system(size: 13))
                    }
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius))
        .padding(.vertical, 2)
    }

    private func flow(_ steps: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    Text(step)
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
                                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                        )
                }
            }
            .padding(.vertical, 3)
        }
        .accessibilityLabel("Flow: \(steps.joined(separator: ", then "))")
    }

    // MARK: - Inline

    private func inlineText(_ runs: [NoteInlineRun], font: Font = .system(size: 14)) -> Text {
        runs.reduce(Text("")) { acc, run in
            let piece: Text = switch run.style {
            case .plain: Text(run.text)
            case .bold: Text(run.text).bold()
            case .italic: Text(run.text).italic()
            case .code: Text(run.text)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(accent)
            }
            return acc + piece
        }
        .font(font)
    }
}
