import Foundation
import OSLog

/// Persists the product registry to `~/Library/Application Support/AgileMaestro/products.json`.
///
/// All read and write operations are atomic: writes go to a temp file and are then
/// swapped into place with `FileManager.replaceItemAt` to prevent partial reads from
/// concurrent observers.
final class ProductService: ProductServiceProtocol {

    // MARK: - Singleton

    static let shared = ProductService()

    // MARK: - Private Properties

    // FileManager is not formally Sendable but is safe to use from multiple contexts
    // when accessed only via its stateless default instance.
    nonisolated(unsafe) private let fileManager: FileManager
    private let logger = Logger.product

    /// Explicit base directory override (used in tests to redirect writes to a temp dir).
    /// When `nil`, defaults to `~/Library/Application Support/AgileMaestro/`.
    private let baseDirectoryOverride: URL?

    /// `~/Library/Application Support/AgileMaestro/`
    private var baseDirectoryURL: URL {
        if let override = baseDirectoryOverride {
            return override
        }
        // swiftlint:disable:next force_unwrapping
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AgileMaestro")
    }

    private var productsFileURL: URL {
        baseDirectoryURL.appendingPathComponent("products.json")
    }

    // MARK: - Init

    /// Creates a `ProductService` that writes to `~/Library/Application Support/AgileMaestro/`.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.baseDirectoryOverride = nil
    }

    /// Creates a `ProductService` that writes to `baseDirectory`.
    ///
    /// Pass a temporary directory URL to isolate tests from the real application support folder.
    init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.baseDirectoryOverride = baseDirectory
    }

    // MARK: - ProductServiceProtocol

    func loadProducts() async throws -> [Product] {
        let url = productsFileURL

        guard fileManager.fileExists(atPath: url.path) else {
            logger.info("products.json not found — returning empty registry")
            return []
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let products = try decoder.decode([Product].self, from: data)
        logger.info("Loaded \(products.count) product(s) from disk")
        return products
    }

    func saveProducts(_ products: [Product]) async throws {
        try ensureBaseDirectory()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(products)

        let destination = productsFileURL
        let tempURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".products.json.tmp")

        try data.write(to: tempURL, options: .atomic)

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: destination)
        }

        logger.info("Saved \(products.count) product(s) to disk")
    }

    func ensureBackupDirectory(for product: Product) async throws {
        let backupURL = product.backupDirectoryURL
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }

        try fileManager.createDirectory(
            at: backupURL,
            withIntermediateDirectories: true
        )
        logger.info("Created backup directory for product \(product.id.uuidString)")
    }

    // MARK: - Private Helpers

    private func ensureBaseDirectory() throws {
        guard !fileManager.fileExists(atPath: baseDirectoryURL.path) else { return }
        try fileManager.createDirectory(
            at: baseDirectoryURL,
            withIntermediateDirectories: true
        )
    }
}
