import Foundation

// MARK: - Notification.Name Extensions

extension Notification.Name {
    /// Posted when the user triggers a session refresh via Cmd+R.
    ///
    /// `MainWindowView` observes this notification and calls
    /// `SessionViewModel.refreshCurrentSession()` in response.
    static let refreshRequested = Notification.Name("AgileMaestro.refreshRequested")
}
