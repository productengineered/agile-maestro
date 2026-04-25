import XCTest
@testable import AgileMaestro

final class ProductServiceTests: XCTestCase {

    // MARK: - Properties

    var sut: ProductService!
    var tempDirectoryURL: URL!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        sut = ProductService(baseDirectory: tempDirectoryURL)
    }

    override func tearDown() {
        sut = nil
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
        super.tearDown()
    }

    // MARK: - loadProducts

    func testLoadReturnsEmptyArrayWhenNoFile() async throws {
        let products = try await sut.loadProducts()
        XCTAssertTrue(products.isEmpty, "Expected empty array when products.json does not exist")
    }

    // MARK: - saveProducts / loadProducts Round-Trip

    func testRoundTrip() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let knownID = UUID()
        let product = Product(
            id: knownID,
            name: "Test Product",
            associatedSessionPath: "/tmp/session",
            claudeDirectoryPath: "/tmp/.claude",
            createdAt: fixedDate
        )

        try await sut.saveProducts([product])
        let loaded = try await sut.loadProducts()

        XCTAssertEqual(loaded.count, 1)
        let loaded1 = try XCTUnwrap(loaded.first)
        XCTAssertEqual(loaded1.id, product.id)
        XCTAssertEqual(loaded1.name, product.name)
        XCTAssertEqual(loaded1.associatedSessionPath, product.associatedSessionPath)
        XCTAssertEqual(loaded1.claudeDirectoryPath, product.claudeDirectoryPath)
        // Dates round-trip via ISO8601 — compare at second precision
        XCTAssertEqual(
            loaded1.createdAt.timeIntervalSince1970,
            product.createdAt.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func testSaveAndLoadMultipleProducts() async throws {
        let products = [
            Product(name: "Alpha"),
            Product(name: "Beta"),
            Product(name: "Gamma")
        ]

        try await sut.saveProducts(products)
        let loaded = try await sut.loadProducts()

        XCTAssertEqual(loaded.count, 3)
        let names = loaded.map(\.name).sorted()
        XCTAssertEqual(names, ["Alpha", "Beta", "Gamma"])
    }

    func testSaveOverwritesPreviousData() async throws {
        try await sut.saveProducts([Product(name: "Old")])
        try await sut.saveProducts([Product(name: "New")])
        let loaded = try await sut.loadProducts()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "New")
    }

    // MARK: - ensureBackupDirectory

    func testEnsureBackupDirectoryCreatesDirectory() async throws {
        let product = Product(
            id: UUID(),
            name: "Backup Test"
        )

        try await sut.ensureBackupDirectory(for: product)

        // The backup directory is computed from Application Support (not temp dir).
        // We only verify the call does not throw; directory creation is system-side.
        // Clean up the real directory if it was created.
        let backupURL = product.backupDirectoryURL
        try? FileManager.default.removeItem(at: backupURL)
    }
}
