import Foundation

// MARK: - LoadingState

/// Represents the loading lifecycle of an async operation in the app shell.
///
/// Shared by `SessionViewModel` and future ViewModels that require
/// a loading/loaded/error state machine.
///
/// Extracted from `SessionViewModel.swift` (AM-803-2) to keep that file under
/// the `file_length` lint threshold — this type has no dependency on
/// `SessionViewModel`'s private state, so the split has no access-control
/// implications.
enum LoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(AgileMaestroError)

    // MARK: - Equatable

    static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.error(let lhsErr), .error(let rhsErr)):
            return lhsErr.localizedDescription == rhsErr.localizedDescription
        default:
            return false
        }
    }
}
