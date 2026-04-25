import XCTest
@testable import AgileMaestro

// MARK: - NewProductSheetViewModelTests

@MainActor
final class NewProductSheetViewModelTests: XCTestCase {

    // MARK: - Properties

    private var sut: NewProductSheetViewModel!
    private var sessionViewModel: SessionViewModel!
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
        sessionViewModel = SessionViewModel(
            productService: mockProductService,
            sessionService: mockSessionService,
            parserService: mockParserService,
            backupService: mockBackupService
        )
        sut = NewProductSheetViewModel(sessionViewModel: sessionViewModel,
                                       sessionService: mockSessionService)
    }

    override func tearDown() {
        sut = nil
        sessionViewModel = nil
        mockProductService = nil
        mockSessionService = nil
        mockParserService = nil
        mockBackupService = nil
        super.tearDown()
    }

    // MARK: - isCreateEnabled

    func testIsCreateEnabled_InitialState_IsFalse() {
        XCTAssertFalse(sut.isCreateEnabled)
    }

    func testIsCreateEnabled_NameOnly_SessionSource_IsFalse() {
        sut.name = "My Product"
        // directorySource defaults to .session but no session is selected
        XCTAssertFalse(sut.isCreateEnabled)
    }

    func testIsCreateEnabled_NameAndSession_IsTrue() {
        let session = TaskSession.fixture()
        sut.availableSessions = [session]
        sut.name = "My Product"
        sut.selectedSession = session
        XCTAssertTrue(sut.isCreateEnabled)
    }

    func testIsCreateEnabled_WhitespaceName_IsFalse() {
        let session = TaskSession.fixture()
        sut.availableSessions = [session]
        sut.name = "   "
        sut.selectedSession = session
        XCTAssertFalse(sut.isCreateEnabled)
    }

    func testIsCreateEnabled_BrowseSource_WithPath_IsTrue() {
        sut.name = "My Product"
        sut.directorySource = .browse
        sut.taskDirectoryPath = "/Users/test/myproject"
        XCTAssertTrue(sut.isCreateEnabled)
    }

    func testIsCreateEnabled_BrowseSource_EmptyPath_IsFalse() {
        sut.name = "My Product"
        sut.directorySource = .browse
        sut.taskDirectoryPath = ""
        XCTAssertFalse(sut.isCreateEnabled)
    }

    // MARK: - State Transitions

    func testSheetState_InitialState_IsIdle() {
        if case .idle = sut.sheetState {
            // pass
        } else {
            XCTFail("Expected .idle, got \(sut.sheetState)")
        }
    }

    func testTransitionToEditing_WhenNameChangesFromIdle() {
        sut.name = "Product"
        if case .editing = sut.sheetState {
            // pass
        } else {
            XCTFail("Expected .editing, got \(sut.sheetState)")
        }
    }

    func testTransitionToEditing_WhenDirectorySourceChangesFromIdle() {
        sut.directorySource = .browse
        if case .editing = sut.sheetState {
            // pass
        } else {
            XCTFail("Expected .editing, got \(sut.sheetState)")
        }
    }

    func testTransitionToEditing_WhenSelectedSessionChangesFromIdle() {
        let session = TaskSession.fixture()
        sut.selectedSession = session
        if case .editing = sut.sheetState {
            // pass
        } else {
            XCTFail("Expected .editing, got \(sut.sheetState)")
        }
    }

    func testTransitionToEditing_FromError_ReturnsToEditing() {
        sut.sheetState = .error("Something failed")
        sut.name = "Updated Name"
        if case .editing = sut.sheetState {
            // pass
        } else {
            XCTFail("Expected .editing after name change from error, got \(sut.sheetState)")
        }
    }

    func testTransitionToEditing_DoesNotOverrideSaving() {
        sut.sheetState = .saving
        sut.name = "New name"
        if case .saving = sut.sheetState {
            // pass — saving state must not be overridden
        } else {
            XCTFail("Expected .saving to be preserved, got \(sut.sheetState)")
        }
    }

    func testCreateProduct_Success_TransitionsToDismissed() async {
        let session = TaskSession.fixture()
        sut.name = "New Product"
        sut.directorySource = .session
        sut.selectedSession = session
        mockProductService.saveProductsResult = .success(())

        await sut.createProduct()

        if case .dismissed = sut.sheetState {
            // pass
        } else {
            XCTFail("Expected .dismissed, got \(sut.sheetState)")
        }
    }

    func testCreateProduct_Failure_TransitionsToError() async {
        let session = TaskSession.fixture()
        sut.name = "New Product"
        sut.directorySource = .session
        sut.selectedSession = session
        mockProductService.saveProductsResult = .failure(ProductSheetTestError.saveFailure)

        await sut.createProduct()

        if case .error = sut.sheetState {
            // pass
        } else {
            XCTFail("Expected .error, got \(sut.sheetState)")
        }
    }

    func testCreateProduct_WhenDisabled_DoesNotTransitionToSaving() async {
        // isCreateEnabled is false (empty name)
        await sut.createProduct()
        if case .idle = sut.sheetState {
            // pass — state unchanged
        } else {
            XCTFail("Expected .idle to be preserved, got \(sut.sheetState)")
        }
    }

    // MARK: - loadSessions (bug 209: independent session discovery)

    func testLoadSessions_PopulatesAvailableSessions_FromService() async {
        // Given: sessionViewModel.sessions is empty, but service returns sessions
        let session1 = TaskSession.fixture()
        let session2 = TaskSession.fixture()
        mockSessionService.getRecentSessionsResult = .success([session1, session2])

        // When
        await sut.loadSessions()

        // Then: sessions come from the service, not from sessionViewModel
        XCTAssertEqual(sut.availableSessions.count, 2)
    }

    func testLoadSessions_WhenServiceFails_SetsEmptyList() async {
        // Given: a stale session already loaded, and the service will now fail
        sut.availableSessions = [TaskSession.fixture()]
        mockSessionService.getRecentSessionsResult = .failure(ProductSheetTestError.saveFailure)

        // When
        await sut.loadSessions()

        // Then: stale data is cleared on failure
        XCTAssertTrue(sut.availableSessions.isEmpty)
    }

    func testLoadSessions_IndependentOfSessionViewModelSessions() async {
        // Given: sessionViewModel.sessions is empty (simulates post-delete state)
        XCTAssertTrue(sessionViewModel.sessions.isEmpty)
        let session = TaskSession.fixture()
        mockSessionService.getRecentSessionsResult = .success([session])

        // When
        await sut.loadSessions()

        // Then: picker is populated despite sessionViewModel being empty
        XCTAssertFalse(sut.availableSessions.isEmpty,
                       "loadSessions must populate even when sessionViewModel.sessions is empty")
    }

    // MARK: - isSaving / errorMessage

    func testIsSaving_WhenSavingState_IsTrue() {
        sut.sheetState = .saving
        XCTAssertTrue(sut.isSaving)
    }

    func testIsSaving_WhenNotSaving_IsFalse() {
        XCTAssertFalse(sut.isSaving)
    }

    func testErrorMessage_WhenErrorState_ReturnsMessage() {
        sut.sheetState = .error("Disk full")
        XCTAssertEqual(sut.errorMessage, "Disk full")
    }

    func testErrorMessage_WhenNotError_IsNil() {
        XCTAssertNil(sut.errorMessage)
    }
}

// MARK: - EditProductSheetViewModelTests

@MainActor
final class EditProductSheetViewModelTests: XCTestCase {

    // MARK: - Properties

    private var sut: EditProductSheetViewModel!
    private var sessionViewModel: SessionViewModel!
    private var mockProductService: MockProductService!
    private var mockSessionService: MockSessionService!
    private var mockParserService: MockParserService!
    private var mockBackupService: MockBackupService!
    private var testProduct: Product!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        mockProductService = MockProductService()
        mockSessionService = MockSessionService()
        mockParserService = MockParserService()
        mockBackupService = MockBackupService()
        sessionViewModel = SessionViewModel(
            productService: mockProductService,
            sessionService: mockSessionService,
            parserService: mockParserService,
            backupService: mockBackupService
        )
        testProduct = Product(
            name: "Agile Maestro",
            associatedSessionPath: NSHomeDirectory() + "/Code/agile-maestro",
            claudeDirectoryPath: NSHomeDirectory() + "/Code/agile-maestro/.claude"
        )
        sut = EditProductSheetViewModel(product: testProduct, sessionViewModel: sessionViewModel)
    }

    override func tearDown() {
        sut = nil
        sessionViewModel = nil
        testProduct = nil
        mockProductService = nil
        mockSessionService = nil
        mockParserService = nil
        mockBackupService = nil
        super.tearDown()
    }

    // MARK: - isSaveEnabled

    func testIsSaveEnabled_InitialState_IsFalse() {
        XCTAssertFalse(sut.isSaveEnabled)
    }

    func testIsSaveEnabled_AfterNameChange_IsTrue() {
        sut.name = "Renamed Product"
        XCTAssertTrue(sut.isSaveEnabled)
    }

    func testIsSaveEnabled_AfterPathChange_IsTrue() {
        sut.taskDirectoryPath = "~/Code/different-project"
        XCTAssertTrue(sut.isSaveEnabled)
    }

    func testIsSaveEnabled_EmptyName_IsFalse() {
        sut.name = ""
        XCTAssertFalse(sut.isSaveEnabled)
    }

    func testIsSaveEnabled_WhitespaceName_IsFalse() {
        sut.name = "   "
        XCTAssertFalse(sut.isSaveEnabled)
    }

    func testIsSaveEnabled_ErrorState_IsTrue_WhenNameNonEmpty() {
        sut.sheetState = .error("Previous save failed")
        XCTAssertTrue(sut.isSaveEnabled)
    }

    func testIsSaveEnabled_SavingState_IsFalse() {
        sut.name = "Changed"
        sut.sheetState = .saving
        XCTAssertFalse(sut.isSaveEnabled)
    }

    // MARK: - abbreviatePath round-trip

    func testAbbreviatePath_HomeDirectory_IsTildeExpanded() {
        let home = NSHomeDirectory()
        let absolute = home + "/Code/myproject"
        let abbreviated = EditProductSheetViewModel.abbreviatePath(absolute)
        XCTAssertEqual(abbreviated, "~/Code/myproject")
    }

    func testAbbreviatePath_NonHomePath_IsUnchanged() {
        let path = "/private/tmp/workspace"
        let abbreviated = EditProductSheetViewModel.abbreviatePath(path)
        XCTAssertEqual(abbreviated, path)
    }

    func testAbbreviatePath_EmptyString_ReturnsEmpty() {
        XCTAssertEqual(EditProductSheetViewModel.abbreviatePath(""), "")
    }

    func testAbbreviatePath_ExactHomeDirectory_ReturnsTilde() {
        let home = NSHomeDirectory()
        let abbreviated = EditProductSheetViewModel.abbreviatePath(home)
        XCTAssertEqual(abbreviated, "~")
    }

    func testInit_PreFillsFieldsFromProduct() {
        XCTAssertEqual(sut.name, "Agile Maestro")
        XCTAssertEqual(sut.taskDirectoryPath, "~/Code/agile-maestro")
        XCTAssertEqual(sut.toolkitDirectoryPath, "~/Code/agile-maestro/.claude")
    }

    func testProductName_ReturnsOriginalName() {
        XCTAssertEqual(sut.productName, "Agile Maestro")
    }

    // MARK: - State Transitions

    func testSheetState_InitialState_IsLoaded() {
        XCTAssertEqual(sut.sheetState, .loaded)
    }

    func testTransitionToDirty_WhenNameChangesFromLoaded() {
        sut.name = "Changed Name"
        XCTAssertEqual(sut.sheetState, .dirty)
    }

    func testTransitionToDirty_WhenTaskPathChanges() {
        sut.taskDirectoryPath = "~/Code/other"
        XCTAssertEqual(sut.sheetState, .dirty)
    }

    func testTransitionToDirty_WhenToolkitPathChanges() {
        sut.toolkitDirectoryPath = "~/Code/other/.claude"
        XCTAssertEqual(sut.sheetState, .dirty)
    }

    func testTransitionToDirty_FromError_ReturnsDirty() {
        sut.sheetState = .error("Previous error")
        sut.name = "Changed"
        XCTAssertEqual(sut.sheetState, .dirty)
    }

    func testTransitionToDirty_DoesNotOverrideSaving() {
        sut.sheetState = .saving
        sut.name = "Changed during save"
        XCTAssertEqual(sut.sheetState, .saving)
    }

    func testSaveProduct_Success_TransitionsToDismissed() async {
        // Pre-seed the product into sessionViewModel so updateProduct can find it by ID
        mockProductService.loadProductsResult = .success([testProduct])
        await sessionViewModel.loadProducts()

        sut.name = "Updated Name"
        mockProductService.saveProductsResult = .success(())

        await sut.saveProduct()

        XCTAssertEqual(sut.sheetState, .dismissed)
    }

    func testSaveProduct_Failure_TransitionsToError() async {
        sut.name = "Updated Name"
        mockProductService.saveProductsResult = .failure(ProductSheetTestError.saveFailure)

        await sut.saveProduct()

        if case .error = sut.sheetState {
            // pass
        } else {
            XCTFail("Expected .error, got \(sut.sheetState)")
        }
    }

    func testSaveProduct_WhenNotEnabled_DoesNotTransitionToSaving() async {
        // isSaveEnabled is false (loaded state, no changes)
        await sut.saveProduct()
        XCTAssertEqual(sut.sheetState, .loaded)
    }

    func testDeleteProduct_Success_TransitionsToDismissedDeleted() async {
        mockProductService.saveProductsResult = .success(())

        await sut.deleteProduct()

        XCTAssertEqual(sut.sheetState, .dismissedDeleted)
    }

    func testDeleteProduct_Failure_TransitionsToError() async {
        mockProductService.saveProductsResult = .failure(ProductSheetTestError.saveFailure)

        await sut.deleteProduct()

        if case .error = sut.sheetState {
            // pass
        } else {
            XCTFail("Expected .error, got \(sut.sheetState)")
        }
    }

    // MARK: - isSaving / isDeleting / errorMessage

    func testIsSaving_WhenSavingState_IsTrue() {
        sut.sheetState = .saving
        XCTAssertTrue(sut.isSaving)
    }

    func testIsDeleting_WhenDeletingState_IsTrue() {
        sut.sheetState = .deleting
        XCTAssertTrue(sut.isDeleting)
    }

    func testErrorMessage_WhenErrorState_ReturnsMessage() {
        sut.sheetState = .error("Save failed")
        XCTAssertEqual(sut.errorMessage, "Save failed")
    }

    func testErrorMessage_WhenNotError_IsNil() {
        XCTAssertNil(sut.errorMessage)
    }
}

// MARK: - Shared Test Helpers

private enum ProductSheetTestError: Error {
    case saveFailure
}

private extension TaskSession {
    static func fixture() -> TaskSession {
        TaskSession(
            id: UUID(),
            path: URL(fileURLWithPath: NSHomeDirectory() + "/Code/test-project"),
            modifiedDate: Date()
        )
    }
}
