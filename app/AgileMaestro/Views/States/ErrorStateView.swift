import SwiftUI

// MARK: - ErrorStateView

/// Full-area error display with a retry action.
///
/// Displayed when `SessionViewModel.state == .error(AgileMaestroError)`. Shows the
/// error description and optional recovery suggestion from `AgileMaestroError`. The
/// "Try Again" button is the focal element, styled `.borderedProminent` to draw the
/// eye and signal the primary recovery path.
///
/// The `onRetry` closure is provided by the caller (typically
/// `Task { await sessionViewModel.refreshCurrentSession() }`).
struct ErrorStateView: View {

    // MARK: - Properties

    let error: AgileMaestroError
    let onRetry: () -> Void

    // MARK: - Body

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Something Went Wrong")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.multicolor)
            }
        } description: {
            VStack(spacing: 8) {
                if let description = error.errorDescription {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
        } actions: {
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityLabel("Try Again")
                .accessibilityHint("Retries loading the current session")
        }
    }
}

// MARK: - Preview

#Preview {
    ErrorStateView(
        error: .sessionDirectoryNotReadable(path: URL(fileURLWithPath: "/tasks")),
        onRetry: { }
    )
    .frame(width: 800, height: 600)
}
