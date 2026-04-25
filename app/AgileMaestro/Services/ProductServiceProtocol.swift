import Foundation

/// Protocol defining CRUD operations for `Product` persistence.
///
/// Conforming types store the product registry as a JSON array in
/// `~/Library/Application Support/AgileMaestro/products.json`.
/// The protocol is designed for dependency injection and unit-test isolation.
protocol ProductServiceProtocol: Sendable {

    /// Loads all registered products from disk.
    ///
    /// Returns an empty array if `products.json` does not yet exist.
    ///
    /// - Returns: Decoded products sorted by creation date ascending.
    /// - Throws: If the file exists but cannot be read or decoded.
    func loadProducts() async throws -> [Product]

    /// Persists the full products array to disk atomically.
    ///
    /// Writes to a temporary file first and then uses `FileManager.replaceItemAt`
    /// to guarantee the on-disk file is never partially written.
    ///
    /// - Parameter products: The complete set of products to persist.
    /// - Throws: If encoding fails or the file cannot be written.
    func saveProducts(_ products: [Product]) async throws

    /// Creates the backup directory structure for a product.
    ///
    /// Ensures `~/Library/Application Support/AgileMaestro/products/<uuid>/backups/`
    /// exists, creating intermediate directories as needed.
    ///
    /// - Parameter product: The product whose backup directory should be created.
    /// - Throws: If the directory cannot be created.
    func ensureBackupDirectory(for product: Product) async throws
}
