import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.agilemaestro"

    /// General app lifecycle and startup events.
    static let app = Logger(subsystem: subsystem, category: "app")

    /// JSON parsing and decoding operations.
    static let parser = Logger(subsystem: subsystem, category: "parser")

    /// File system watcher events and FSEvents callbacks.
    static let watcher = Logger(subsystem: subsystem, category: "watcher")

    /// Product loading and directory resolution.
    static let product = Logger(subsystem: subsystem, category: "product")

    /// Backup creation and restoration.
    static let backup = Logger(subsystem: subsystem, category: "backup")

    /// Team manifest loading and agent roster operations.
    static let manifest = Logger(subsystem: subsystem, category: "manifest")

    /// Core Data stack and persistence operations.
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
