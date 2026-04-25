import Foundation
@testable import AgileMaestro

// MARK: - MockManifestService

/// A test double for `ManifestServiceProtocol` with configurable result and call tracking.
///
/// Inject into ViewModels under test to avoid filesystem access.
/// Mutable state is protected by `NSLock` to satisfy `Sendable` without data races.
final class MockManifestService: ManifestServiceProtocol, @unchecked Sendable {

    // MARK: - Private State

    private let lock = NSLock()
    private var _loadManifestResult: Result<AgentManifest, Error> = .success(.preview)
    private var _loadManifestCallCount: Int = 0
    private var _lastClaudeDir: URL?

    // MARK: - Configuration

    /// The result to return on the next `loadManifest` call.
    var loadManifestResult: Result<AgentManifest, Error> {
        get { lock.withLock { _loadManifestResult } }
        set { lock.withLock { _loadManifestResult = newValue } }
    }

    // MARK: - Call Tracking

    /// Number of times `loadManifest(from:)` was called.
    var loadManifestCallCount: Int {
        lock.withLock { _loadManifestCallCount }
    }

    /// The last URL passed to `loadManifest(from:)`.
    var lastClaudeDir: URL? {
        lock.withLock { _lastClaudeDir }
    }

    // MARK: - ManifestServiceProtocol

    func loadManifest(from claudeDir: URL) async throws -> AgentManifest {
        let result: Result<AgentManifest, Error> = lock.withLock {
            _loadManifestCallCount += 1
            _lastClaudeDir = claudeDir
            return _loadManifestResult
        }
        return try result.get()
    }

    // MARK: - Convenience Helpers

    /// Configures the mock to throw the given error on the next call.
    func setError(_ error: Error) {
        lock.withLock { _loadManifestResult = .failure(error) }
    }

    /// Configures the mock to return the given manifest on the next call.
    func setManifest(_ manifest: AgentManifest) {
        lock.withLock { _loadManifestResult = .success(manifest) }
    }

    /// Resets call count and last URL, leaving the configured result unchanged.
    func resetCallTracking() {
        lock.withLock {
            _loadManifestCallCount = 0
            _lastClaudeDir = nil
        }
    }
}
