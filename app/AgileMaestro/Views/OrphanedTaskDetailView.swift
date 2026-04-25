import SwiftUI

// MARK: - OrphanedTaskDetailView

/// Read-only detail panel for a selected `OrphanedTask`.
///
/// Layout (top to bottom inside a ScrollView):
/// 1. **Error Banner** — prominent red/orange banner with error icon and message
/// 2. **Filename** — displayed prominently; tapping opens the file in the default app
/// 3. **Partial Fields** — any key-value pairs extractable before parse failure
/// 4. **Raw JSON** — monospace scrollable dump of the full file contents
struct OrphanedTaskDetailView: View {

    @Environment(SessionViewModel.self) private var sessionViewModel

    let task: OrphanedTask

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Error Banner
                errorBanner

                // 2. Filename header
                filenameHeader

                // 3. Partial Fields
                if !task.partialFields.isEmpty {
                    partialFieldsCard
                }

                // 4. Raw JSON
                rawJSONCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error Banner

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .symbolRenderingMode(.monochrome)

            VStack(alignment: .leading, spacing: 4) {
                Text("Parse Error")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text(task.errorMessage)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.red, Color.orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Parse error: \(task.errorMessage)")
    }

    // MARK: - File URL

    private var taskFileURL: URL? {
        guard let sessionPath = sessionViewModel.selectedSession?.path else { return nil }
        return sessionPath.appendingPathComponent(task.filename)
    }

    // MARK: - Filename Header

    private var filenameHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Corrupted File")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)

            Text(task.filename)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            // Clickable filename link
            if let fileURL = taskFileURL {
                OrphanedTaskFilePathLink(fileName: fileURL.lastPathComponent, fileURL: fileURL)
            }
        }
    }

    // MARK: - Partial Fields

    private var partialFieldsCard: some View {
        CardView(title: "Partial Fields", icon: "doc.questionmark", iconColor: .orange) {
            VStack(alignment: .leading, spacing: 0) {
                let sortedKeys = task.partialFields.keys.sorted()
                ForEach(Array(sortedKeys.enumerated()), id: \.element) { index, key in
                    PartialFieldRow(
                        key: key,
                        value: task.partialFields[key] ?? ""
                    )
                    if index < sortedKeys.count - 1 {
                        Divider()
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Raw JSON

    private var rawJSONCard: some View {
        CardView(title: "Raw File Contents", icon: "curlybraces", iconColor: .secondary) {
            if task.rawJSON.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                    Text("File could not be read")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if task.rawJSON.utf8.count == 100 * 1024 {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Contents truncated at 100 KB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(task.rawJSON)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

// MARK: - OrphanedTaskFilePathLink

/// A tappable row showing the orphaned task's JSON filename. Clicking opens the file
/// in the system's default application. Mirrors `TaskFilePathLink` in DetailHeaderView.
private struct OrphanedTaskFilePathLink: View {

    let fileName: String
    let fileURL: URL

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(fileName)
                .font(.caption2)
                .foregroundStyle(isHovered ? .secondary : .tertiary)
                .underline(isHovered)
                .animation(.easeInOut(duration: 0.1), value: isHovered)
        }
        .onTapGesture {
            NSWorkspace.shared.open(fileURL)
        }
        .onHover { hovered in
            isHovered = hovered
            if hovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                NSCursor.pop()
                isHovered = false
            }
        }
        .help(fileURL.path)
        .accessibilityLabel("Open task file \(fileName)")
        .accessibilityHint("Opens \(fileURL.path) in the default application")
    }
}

// MARK: - PartialFieldRow

/// A single monospace key-value row used in the Partial Fields card.
private struct PartialFieldRow: View {

    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .leading)
                .textSelection(.enabled)

            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key): \(value)")
    }
}

// MARK: - Preview

#Preview("OrphanedTaskDetailView — With Partial Fields") {
    let task = OrphanedTask(
        filename: "task-abc123.json",
        errorMessage: "The data couldn't be read because it isn't in the correct format.",
        partialFields: [
            "id": "abc123",
            "subject": "Task: Fix something important",
            "status": "in_progress"
        ],
        rawJSON: """
        {
          "id": "abc123",
          "subject": "Task: Fix something important",
          "status": "in_progress",
          "metadata": { INVALID JSON HERE
        """
    )
    return OrphanedTaskDetailView(task: task)
        .frame(width: 600, height: 600)
        .background(Color(.windowBackgroundColor))
}

#Preview("OrphanedTaskDetailView — No Partial Fields") {
    let task = OrphanedTask(
        filename: "task-broken.json",
        errorMessage: "The file contains binary data that cannot be decoded as UTF-8.",
        partialFields: [:],
        rawJSON: "{\u{FFFD}\u{FFFD}\u{FFFD}invalid binary\u{FFFD}}"
    )
    return OrphanedTaskDetailView(task: task)
        .frame(width: 600, height: 400)
        .background(Color(.windowBackgroundColor))
}

#Preview("OrphanedTaskDetailView — Unreadable File") {
    let task = OrphanedTask(
        filename: "task-unreadable.json",
        errorMessage: "The operation couldn't be completed. (NSCocoaErrorDomain error 257.)",
        partialFields: [:],
        rawJSON: ""
    )
    return OrphanedTaskDetailView(task: task)
        .frame(width: 600, height: 300)
        .background(Color(.windowBackgroundColor))
}
