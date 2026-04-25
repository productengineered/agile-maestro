import XCTest
@testable import AgileMaestro

// MARK: - SessionViewModelCRUDTests

/// Tests for `SessionViewModel.createProduct`, `updateProduct`, and `removeProduct`.
///
/// Mock services (`MockProductService`, `MockSessionService`, `MockParserService`,
/// `MockBackupService`) are defined in `SessionViewModelTests.swift` and are
/// accessible within the same test target.
@MainActor
final class SessionViewModelCRUDTests: XCTestCase {

    // MARK: - Properties

    private var sut: SessionViewModel!
    private var mockProductService: MockProductService!
    private var mockSessionService: MockSessionService!
    private var mockParserService: MockParserService!
    private var mockBackupService: MockBackupService!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        mockProductService = MockProductService()
        mockSessionService = MockSessionService()
        mockParserService = MockParserService()
        mockBackupService = MockBackupService()
        sut = SessionViewModel(
            productService: mockProductService,
            sessionService: mockSessionService,
            parserService: mockParserService,
            backupService: mockBackupService,
            fileWatcher: FileWatcherService()
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockProductService = nil
        mockSessionService = nil
        mockParserService = nil
        mockBackupService = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Primes `sut.products` with `products` via `loadProducts()`.
    private func loadProducts(_ products: [Product]) async {
        mockProductService.loadProductsResult = .success(products)
        mockSessionService.getRecentSessionsResult = .success([])
        await sut.loadProducts()
    }

    // MARK: - createProduct

    func testCreateProductAppendsToProductsAndSetsSelectedProduct() async throws {
        // Given — start with one existing product
        await loadProducts([Product(name: "Existing")])

        // When
        try await sut.createProduct(
            name: "New Product",
            taskDirectoryPath: "/tmp/tasks",
            toolkitDirectoryPath: nil
        )

        // Then
        XCTAssertEqual(sut.products.count, 2, "products should contain existing + newly created")
        XCTAssertEqual(sut.selectedProduct?.name, "New Product",
                       "selectedProduct should be set to the newly created product")
        XCTAssertTrue(mockProductService.saveProductsCalled)
        XCTAssertEqual(mockProductService.savedProducts.count, 2)
    }

    func testCreateProductPropagatesSaveError() async {
        struct SaveError: Error {}
        mockProductService.saveProductsResult = .failure(SaveError())

        do {
            try await sut.createProduct(
                name: "Broken",
                taskDirectoryPath: "/tmp/tasks",
                toolkitDirectoryPath: nil
            )
            XCTFail("Expected createProduct to throw when save fails")
        } catch {
            // Expected
        }
        XCTAssertTrue(sut.products.isEmpty, "products must not be mutated when save fails")
    }

    // Regression test for: creating a product did not load sessions (bug task-207)
    func testCreateProduct_LoadsSessionsImmediately() async throws {
        // Given — prime the session service with a session in the target directory
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let session = TaskSession(id: UUID(), path: dir, modifiedDate: Date())
        mockSessionService.getRecentSessionsResult = .success([session])
        mockParserService.loadTasksResult = .success([])

        // When
        try await sut.createProduct(
            name: "Session Loader",
            taskDirectoryPath: dir.path,
            toolkitDirectoryPath: nil
        )

        // Then — sessions must have been loaded (state .loaded proves the full path ran)
        XCTAssertEqual(sut.sessions.count, 1,
                       "createProduct must load sessions for the new product immediately")
        XCTAssertEqual(sut.state, .loaded,
                       "state must be .loaded after createProduct triggers session loading")
    }

    func testCreateProductSetsAssociatedSessionPath() async throws {
        try await sut.createProduct(
            name: "Mapped",
            taskDirectoryPath: "/tmp/my-tasks",
            toolkitDirectoryPath: "/tmp/.claude"
        )

        let created = try XCTUnwrap(sut.products.first)
        XCTAssertEqual(created.associatedSessionPath, "/tmp/my-tasks")
        XCTAssertEqual(created.claudeDirectoryPath, "/tmp/.claude")
    }

    // MARK: - updateProduct

    func testUpdateProductReplacesMatchingEntryById() async throws {
        // Given — prime products array with two products
        let original = Product(name: "Original")
        let other = Product(name: "Other")
        await loadProducts([original, other])

        // When
        var updated = original
        updated.name = "Renamed"
        try await sut.updateProduct(updated)

        // Then — the renamed product replaces the original; the other is untouched
        XCTAssertEqual(sut.products.count, 2)
        XCTAssertEqual(sut.products.first(where: { $0.id == original.id })?.name, "Renamed")
        XCTAssertEqual(sut.products.first(where: { $0.id == other.id })?.name, "Other")
        XCTAssertTrue(mockProductService.saveProductsCalled)
    }

    func testUpdateProductRefreshesSelectedProductWhenItIsTheUpdatedOne() async throws {
        // Given
        let original = Product(name: "Original")
        await loadProducts([original])
        XCTAssertEqual(sut.selectedProduct?.name, "Original")

        // When
        var updated = original
        updated.name = "Updated Name"
        try await sut.updateProduct(updated)

        // Then
        XCTAssertEqual(sut.selectedProduct?.name, "Updated Name",
                       "selectedProduct must reflect the updated name when it was the selected product")
    }

    func testUpdateProductDoesNotChangeSelectedProductWhenDifferentProductUpdated() async throws {
        // Given — two products; first is selected
        let selected = Product(name: "Selected")
        let other = Product(name: "Other")
        await loadProducts([selected, other])
        XCTAssertEqual(sut.selectedProduct?.id, selected.id)

        // When — update the other product
        var updatedOther = other
        updatedOther.name = "Other Renamed"
        try await sut.updateProduct(updatedOther)

        // Then — selectedProduct is unchanged
        XCTAssertEqual(sut.selectedProduct?.name, "Selected")
    }

    func testUpdateProductThrowsWhenProductNotFound() async {
        // products array is empty — no matching ID will be found
        let unknown = Product(name: "Ghost")

        do {
            try await sut.updateProduct(unknown)
            XCTFail("Expected updateProduct to throw for an unknown product id")
        } catch {
            // Expected
        }
    }

    // MARK: - removeProduct

    func testRemoveProductRemovesFromProductsArray() async throws {
        // Given
        let alpha = Product(name: "Alpha")
        let beta = Product(name: "Beta")
        await loadProducts([alpha, beta])

        // When
        try await sut.removeProduct(alpha)

        // Then
        XCTAssertEqual(sut.products.count, 1)
        XCTAssertEqual(sut.products.first?.name, "Beta")
        XCTAssertTrue(mockProductService.saveProductsCalled)
    }

    func testRemoveProductSelectsFirstRemainingWhenSelectedProductIsRemoved() async throws {
        // Given
        let first = Product(name: "First")
        let second = Product(name: "Second")
        await loadProducts([first, second])
        XCTAssertEqual(sut.selectedProduct?.id, first.id)

        // When — remove the selected product
        try await sut.removeProduct(first)

        // Then — second product becomes selected
        XCTAssertEqual(sut.selectedProduct?.id, second.id,
                       "First remaining product should be selected after deleting the selected one")
    }

    func testRemoveProductSetsSelectedProductNilWhenNoRemainingProducts() async throws {
        // Given — single product
        let only = Product(name: "Only")
        await loadProducts([only])
        XCTAssertNotNil(sut.selectedProduct)

        // When
        try await sut.removeProduct(only)

        // Then
        XCTAssertNil(sut.selectedProduct,
                     "selectedProduct must be nil when no products remain after deletion")
        XCTAssertTrue(sut.products.isEmpty)
    }

    func testRemoveProductDoesNotChangeSelectedProductWhenDifferentProductRemoved() async throws {
        // Given
        let selected = Product(name: "Selected")
        let other = Product(name: "Other")
        await loadProducts([selected, other])
        XCTAssertEqual(sut.selectedProduct?.id, selected.id)

        // When — remove the non-selected product
        try await sut.removeProduct(other)

        // Then — selectedProduct is unchanged
        XCTAssertEqual(sut.selectedProduct?.id, selected.id,
                       "Removing a non-selected product must not change selectedProduct")
    }

    func testRemoveProductPropagatesSaveError() async throws {
        // Given — one product loaded
        let product = Product(name: "Doomed")
        await loadProducts([product])

        // Configure save to fail
        struct SaveError: Error {}
        mockProductService.saveProductsResult = .failure(SaveError())

        // When / Then
        do {
            try await sut.removeProduct(product)
            XCTFail("Expected removeProduct to throw when save fails")
        } catch {
            // Expected
        }
        XCTAssertEqual(sut.products.count, 1, "products must not be mutated when save fails")
    }
}
