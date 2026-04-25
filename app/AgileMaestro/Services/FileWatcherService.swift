import CoreServices
import Foundation
import OSLog

// MARK: - DirectorySnapshot

/// A point-in-time snapshot of `*.json` files in a directory.
///
/// Captures filename, modification date, and file size for each file.
/// Used to detect additions, modifications, and removals between polls.
struct DirectorySnapshot: Equatable {

    // MARK: - Entry

    struct Entry: Equatable {
        let name: String
        let modificationDate: Date
        let size: Int
    }

    // MARK: - Properties

    let entries: [Entry]

    // MARK: - Init

    /// Captures the current state of `*.json` files in `directory`.
    ///
    /// If the directory is unreadable, `entries` defaults to an empty array.
    init(directory: URL) {
        let fileManager = FileManager.default
        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isHiddenKey
                ],
                options: [.skipsHiddenFiles]
            )
        else {
            entries = []
            return
        }

        var captured: [Entry] = []
        for url in contents {
            guard url.pathExtension == "json" else { continue }
            let resourceValues = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey
            ])
            let date = resourceValues?.contentModificationDate ?? .distantPast
            let size = resourceValues?.fileSize ?? 0
            captured.append(Entry(name: url.lastPathComponent, modificationDate: date, size: size))
        }

        // Stable sort by filename so Equatable comparison is reliable
        entries = captured.sorted { $0.name < $1.name }
    }

    // MARK: - Diff

    struct Diff {
        let added: Set<String>
        let modified: Set<String>
        let removed: Set<String>

        var hasChanges: Bool { !added.isEmpty || !modified.isEmpty || !removed.isEmpty }
    }

    /// Returns the diff between `self` (new) and `previous` (old).
    func diff(from previous: DirectorySnapshot) -> Diff {
        let oldMap = Dictionary(uniqueKeysWithValues: previous.entries.map { ($0.name, $0) })
        let newMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })

        let oldNames = Set(oldMap.keys)
        let newNames = Set(newMap.keys)

        let added = newNames.subtracting(oldNames)
        let removed = oldNames.subtracting(newNames)
        let modified = newNames.intersection(oldNames).filter { name in
            guard let old = oldMap[name], let new = newMap[name] else { return false }
            return old.modificationDate != new.modificationDate || old.size != new.size
        }

        return Diff(added: added, modified: Set(modified), removed: removed)
    }
}

// MARK: - FileWatcherService

/// Watches a directory for file changes using FSEvents (primary) and a
/// DispatchSourceTimer polling backup (fallback for edge cases).
///
/// Thread safety is provided by `NSLock`. The `onChange` callback is always
/// delivered on the main queue after a 0.5-second debounce, so callers can
/// safely update `@Observable` ViewModels without additional dispatching.
///
/// ## Usage
/// ```swift
/// let watcher = FileWatcherService()
/// watcher.onChange = { [weak self] in
///     await self?.reloadTasks()
/// }
/// watcher.start(watching: sessionDirectoryURL)
/// // Later:
/// watcher.stop()
/// ```
final class FileWatcherService {

    // MARK: - Constants

    private static let pollInterval: TimeInterval = 3.0
    private static let debounceInterval: TimeInterval = 0.5

    // MARK: - Public Properties

    /// Called on the main queue whenever the watched directory changes.
    var onChange: (@Sendable () -> Void)?

    // MARK: - Private Properties

    private let lock = NSLock()
    private var watchedDirectory: URL?
    private var currentSnapshot: DirectorySnapshot = DirectorySnapshot(directory: URL(fileURLWithPath: "/"))
    private var fsEventStream: FSEventStreamRef?
    private var pollingTimer: DispatchSourceTimer?
    private var debounceWorkItem: DispatchWorkItem?

    private let logger = Logger.watcher
    private let watcherQueue = DispatchQueue(
        label: "com.agilemaestro.filewatcher",
        qos: .utility
    )

    // MARK: - Lifecycle

    deinit {
        stopInternal()
    }

    // MARK: - Public API

    /// Begins watching `directory` for `*.json` file changes.
    ///
    /// Calling `start` while already watching replaces the previous watch.
    func start(watching directory: URL) {
        lock.lock()
        defer { lock.unlock() }

        stopInternal()

        watchedDirectory = directory
        currentSnapshot = DirectorySnapshot(directory: directory)
        logger.info("Starting file watcher for: \(directory.path)")

        startFSEvents(directory: directory)
        startPolling(directory: directory)
    }

    /// Stops all watching and cancels any pending debounce callbacks.
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopInternal()
    }

    // MARK: - Private — FSEvents

    private func startFSEvents(directory: URL) {
        let pathsToWatch = [directory.path] as CFArray
        let latency: CFTimeInterval = 0.25

        // The C callback receives an Unmanaged<FileWatcherService> in its `clientCallBackInfo`.
        // We use `passUnretained` so the C layer holds a non-owning raw pointer; ARC still manages
        // the object lifetime. The stream is always stopped before `self` deinits.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
            guard let info = clientCallBackInfo else { return }
            let service = Unmanaged<FileWatcherService>.fromOpaque(info).takeUnretainedValue()
            service.handleFSEvent()
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            logger.error("Failed to create FSEventStream for: \(directory.path)")
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        fsEventStream = stream
        logger.debug("FSEventStream started")
    }

    private func handleFSEvent() {
        lock.lock()
        let directory = watchedDirectory
        lock.unlock()

        guard let directory else { return }
        logger.debug("FSEvent received for: \(directory.path)")
        checkForChanges(in: directory)
    }

    // MARK: - Private — Polling

    private func startPolling(directory: URL) {
        let timer = DispatchSource.makeTimerSource(queue: watcherQueue)
        timer.schedule(
            deadline: .now() + Self.pollInterval,
            repeating: Self.pollInterval
        )
        timer.setEventHandler { [weak self] in
            self?.handlePollTick(directory: directory)
        }
        timer.resume()
        pollingTimer = timer
        logger.debug("Polling timer started (interval: \(Self.pollInterval)s)")
    }

    private func handlePollTick(directory: URL) {
        logger.debug("Poll tick for: \(directory.path)")
        checkForChanges(in: directory)
    }

    // MARK: - Private — Change Detection

    private func checkForChanges(in directory: URL) {
        let newSnapshot = DirectorySnapshot(directory: directory)

        lock.lock()
        let previousSnapshot = currentSnapshot
        let diff = newSnapshot.diff(from: previousSnapshot)
        lock.unlock()

        guard diff.hasChanges else { return }

        let added = diff.added.count
        let modified = diff.modified.count
        let removed = diff.removed.count
        logger.info("Changes detected — added: \(added) modified: \(modified) removed: \(removed)")

        lock.lock()
        debounceWorkItem?.cancel()
        var workItem: DispatchWorkItem!
        workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            lock.lock()
            currentSnapshot = newSnapshot
            lock.unlock()

            guard !workItem.isCancelled else { return }

            logger.debug("Debounce elapsed — firing onChange")
            let callback = self.onChange
            DispatchQueue.main.async {
                callback?()
            }
        }
        debounceWorkItem = workItem
        lock.unlock()

        watcherQueue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: workItem)
    }

    // MARK: - Private — Stop (must be called with lock held OR from deinit)

    /// Stops and releases all resources. Caller must hold `lock`.
    private func stopInternal() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
            logger.debug("FSEventStream stopped")
        }

        if let timer = pollingTimer {
            timer.cancel()
            pollingTimer = nil
            logger.debug("Polling timer cancelled")
        }

        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        watchedDirectory = nil
    }
}
