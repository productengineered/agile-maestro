import XCTest
@testable import AgileMaestro

// swiftlint:disable:next type_body_length
final class TaskParserServiceTests: XCTestCase {

    // MARK: - Properties

    private var sut: TaskParserService!
    private var tempDir: URL!

    // MARK: - Static JSON Fixtures

    private static let validEpicJSON = """
    {
      "id": "1",
      "subject": "Epic: AM-100 - Foundation",
      "description": "The foundation epic.",
      "status": "pending",
      "blocks": [],
      "blockedBy": [],
      "metadata": {
        "type": "epic",
        "schema_version": "2.0",
        "id": "AM-100",
        "priority": "P1",
        "approval": "approved",
        "blocked": false
      }
    }
    """

    private static let validStoryJSON = """
    {
      "id": "10",
      "subject": "Story: Phase 1",
      "description": "First story.",
      "status": "in_progress",
      "blocks": [],
      "blockedBy": ["1"],
      "metadata": {
        "type": "story",
        "schema_version": "2.0",
        "parent": "1",
        "priority": "P2",
        "approval": "approved",
        "blocked": false
      }
    }
    """

    private static let malformedJSON = "{broken"

    // settings.json and config.json should be excluded as non-task files
    private static let settingsJSON = """
    { "version": "1.0", "theme": "dark" }
    """

    private static let configJSON = """
    { "apiEndpoint": "https://example.com" }
    """

    // A minimal ClaudeTask — valid JSON with id+subject but no metadata.schema_version
    private static let claudeTaskJSON = """
    {
      "id": "42",
      "subject": "Fix login button tap area",
      "description": "The button is too small on compact displays.",
      "status": "in_progress",
      "blocks": ["50"],
      "blockedBy": ["40"],
      "priority": "P2",
      "owner": "alice"
    }
    """

    // Valid JSON but missing both id and subject
    private static let missingIDAndSubjectJSON = """
    {
      "description": "A task with no id or subject.",
      "status": "pending"
    }
    """

    // Valid JSON with id but missing subject
    private static let missingSubjectJSON = """
    {
      "id": "99",
      "description": "Has id but no subject field."
    }
    """

    // JSON where metadata is a non-object value (integer) so:
    // 1. JSONSerialization sees `metadata` as an NSNumber, not [String: Any].
    //    → metadata?["schema_version"] is nil → hasSchemaVersion == false
    //    → no id/subject → OrphanedTask (missing required fields path).
    // This test verifies a non-dict metadata blob → OrphanedTask.
    private static let brokenMetadataJSON = """
    {
      "subject": "Metadata is a number",
      "status": "pending",
      "metadata": 42
    }
    """

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        sut = TaskParserService()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Write fixture files
        write(Self.validEpicJSON, to: tempDir.appendingPathComponent("1.json"))
        write(Self.malformedJSON, to: tempDir.appendingPathComponent("2.json"))
        write(Self.validStoryJSON, to: tempDir.appendingPathComponent("10.json"))
        write(Self.settingsJSON, to: tempDir.appendingPathComponent("settings.json"))
        write(Self.configJSON, to: tempDir.appendingPathComponent("config.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testExcludesNonTaskFiles() async throws {
        let result = try await sut.loadTasks(from: tempDir)
        // Only 1.json and 10.json are valid structured task files; 2.json is malformed (orphaned);
        // settings.json and config.json are excluded by name.
        XCTAssertEqual(result.structuredTasks.count, 2)
    }

    func testSkipsMalformedFiles() async throws {
        // Malformed 2.json should be classified as orphaned, not structured.
        let result = try await sut.loadTasks(from: tempDir)
        let ids = result.structuredTasks.map { $0.id }
        XCTAssertFalse(ids.contains("2"), "Malformed file should not produce a structured task")
        XCTAssertEqual(result.orphanedTasks.count, 1)
        XCTAssertEqual(result.orphanedTasks.first?.filename, "2.json")
    }

    func testSortsNumerically() async throws {
        let result = try await sut.loadTasks(from: tempDir)
        let tasks = result.structuredTasks
        XCTAssertEqual(tasks.count, 2)
        // Numeric sort: 1 comes before 10 (not lexicographic "10" < "1")
        XCTAssertEqual(tasks[0].id, "1")
        XCTAssertEqual(tasks[1].id, "10")
    }

    func testSourceFileIsSetAfterParsing() async throws {
        let result = try await sut.loadTasks(from: tempDir)
        for task in result.structuredTasks {
            XCTAssertNotNil(task.sourceFile, "sourceFile should be set by parser")
        }
    }

    func testEpicTaskDecoded() async throws {
        let result = try await sut.loadTasks(from: tempDir)
        let epic = result.structuredTasks.first { $0.id == "1" }
        XCTAssertNotNil(epic)
        XCTAssertEqual(epic?.type, .epic)
        XCTAssertEqual(epic?.subject, "Epic: AM-100 - Foundation")
    }

    func testEmptyDirectoryReturnsEmptyArray() async throws {
        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let result = try await sut.loadTasks(from: emptyDir)
        XCTAssertTrue(result.structuredTasks.isEmpty)
        XCTAssertTrue(result.claudeTasks.isEmpty)
        XCTAssertTrue(result.orphanedTasks.isEmpty)
    }

    func testNonExistentDirectoryThrows() async {
        let nonExistent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            _ = try await sut.loadTasks(from: nonExistent)
            XCTFail("Expected an error to be thrown for non-existent directory")
        } catch {
            // Expected — any error is acceptable
        }
    }

    func testPeekSessionInfoReturnsEpicName() async {
        let info = await sut.peekSessionInfo(in: tempDir)
        XCTAssertEqual(info.epicName, "AM-100 - Foundation", "Should strip 'Epic: ' prefix")
        XCTAssertEqual(info.epicDisplayId, "AM-100")
    }

    func testPeekSessionInfoTaskCount() async {
        let info = await sut.peekSessionInfo(in: tempDir)
        // 3 json files that are not excluded: 1.json, 2.json, 10.json
        XCTAssertEqual(info.taskCount, 3)
    }

    // MARK: - Structured Path (Regression Tests)

    func testStructuredPath_producesTaskItemWithSchemaVersion() async throws {
        // Arrange: only the epic fixture has schema_version — use an isolated dir.
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.validEpicJSON, to: dir.appendingPathComponent("1.json"))

        // Act
        let result = try await sut.loadTasks(from: dir)

        // Assert
        XCTAssertEqual(result.structuredTasks.count, 1)
        XCTAssertTrue(result.claudeTasks.isEmpty)
        XCTAssertTrue(result.orphanedTasks.isEmpty)
        XCTAssertEqual(result.structuredTasks.first?.id, "1")
        XCTAssertEqual(result.structuredTasks.first?.type, .epic)
    }

    func testStructuredPath_sourceFileIsFilename() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.validEpicJSON, to: dir.appendingPathComponent("1.json"))

        let result = try await sut.loadTasks(from: dir)

        XCTAssertEqual(result.structuredTasks.first?.sourceFile, "1.json")
    }

    // MARK: - ClaudeTask Path

    func testClaudeTaskPath_validJSONWithIDAndSubjectNoSchemaVersion() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.claudeTaskJSON, to: dir.appendingPathComponent("42.json"))

        let result = try await sut.loadTasks(from: dir)

        XCTAssertTrue(result.structuredTasks.isEmpty)
        XCTAssertEqual(result.claudeTasks.count, 1)
        XCTAssertTrue(result.orphanedTasks.isEmpty)
    }

    func testClaudeTaskPath_fieldsDecodedCorrectly() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.claudeTaskJSON, to: dir.appendingPathComponent("42.json"))

        let result = try await sut.loadTasks(from: dir)

        let task = try XCTUnwrap(result.claudeTasks.first)
        XCTAssertEqual(task.id, "42")
        XCTAssertEqual(task.subject, "Fix login button tap area")
        XCTAssertEqual(task.description, "The button is too small on compact displays.")
        XCTAssertEqual(task.status, "in_progress")
        XCTAssertEqual(task.blocks, ["50"])
        XCTAssertEqual(task.blockedBy, ["40"])
    }

    func testClaudeTaskPath_rawFieldsCapturesExtraKeys() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.claudeTaskJSON, to: dir.appendingPathComponent("42.json"))

        let result = try await sut.loadTasks(from: dir)

        let task = try XCTUnwrap(result.claudeTasks.first)
        // "priority" and "owner" are not known ClaudeTask fields — must be in rawFields
        XCTAssertNotNil(task.rawFields["priority"], "rawFields should capture unknown key 'priority'")
        XCTAssertNotNil(task.rawFields["owner"], "rawFields should capture unknown key 'owner'")
        // Known fields must NOT appear in rawFields
        XCTAssertNil(task.rawFields["id"], "rawFields should not duplicate known key 'id'")
        XCTAssertNil(task.rawFields["subject"], "rawFields should not duplicate known key 'subject'")
        XCTAssertNil(task.rawFields["description"], "rawFields should not duplicate known key 'description'")
        XCTAssertNil(task.rawFields["status"], "rawFields should not duplicate known key 'status'")
        XCTAssertNil(task.rawFields["blocks"], "rawFields should not duplicate known key 'blocks'")
        XCTAssertNil(task.rawFields["blockedBy"], "rawFields should not duplicate known key 'blockedBy'")
    }

    // MARK: - OrphanedTask Path

    func testOrphanedPath_invalidJSON() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.malformedJSON, to: dir.appendingPathComponent("bad.json"))

        let result = try await sut.loadTasks(from: dir)

        XCTAssertTrue(result.structuredTasks.isEmpty)
        XCTAssertTrue(result.claudeTasks.isEmpty)
        XCTAssertEqual(result.orphanedTasks.count, 1)
        XCTAssertEqual(result.orphanedTasks.first?.filename, "bad.json")
        XCTAssertFalse(result.orphanedTasks.first?.errorMessage.isEmpty ?? true)
    }

    func testOrphanedPath_emptyFile() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write("", to: dir.appendingPathComponent("empty.json"))

        let result = try await sut.loadTasks(from: dir)

        XCTAssertEqual(result.orphanedTasks.count, 1)
        XCTAssertEqual(result.orphanedTasks.first?.filename, "empty.json")
        XCTAssertEqual(result.orphanedTasks.first?.rawJSON, "")
    }

    func testOrphanedPath_missingIDAndSubject() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.missingIDAndSubjectJSON, to: dir.appendingPathComponent("nofields.json"))

        let result = try await sut.loadTasks(from: dir)

        XCTAssertEqual(result.orphanedTasks.count, 1)
        XCTAssertEqual(result.orphanedTasks.first?.filename, "nofields.json")
    }

    func testOrphanedPath_missingSubjectOnly() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.missingSubjectJSON, to: dir.appendingPathComponent("noid.json"))

        let result = try await sut.loadTasks(from: dir)

        XCTAssertEqual(result.orphanedTasks.count, 1)
        XCTAssertEqual(result.orphanedTasks.first?.filename, "noid.json")
    }

    func testOrphanedPath_nonDictMetadataFieldYieldsOrphanedTask() async throws {
        // When metadata is a non-dict value (e.g. an integer), the schema_version check
        // fails (metadata cannot be cast to [String: Any]) and the file also lacks a
        // top-level id field — resulting in an OrphanedTask via the missing-fields path.
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.brokenMetadataJSON, to: dir.appendingPathComponent("broken.json"))

        let result = try await sut.loadTasks(from: dir)

        XCTAssertTrue(result.structuredTasks.isEmpty, "Non-dict metadata should not yield a structured task")
        XCTAssertTrue(result.claudeTasks.isEmpty, "File with no id should not yield a ClaudeTask")
        XCTAssertEqual(result.orphanedTasks.count, 1)
        XCTAssertEqual(result.orphanedTasks.first?.filename, "broken.json")
    }

    func testOrphanedPath_rawJSONCapsAt100KB() async throws {
        // Build a JSON string well over 100 KB and confirm rawJSON is capped at 100 KB.
        let padding = String(repeating: "x", count: 200_000)
        let largeJSON = """
        {
          "id": "\(padding)",
          "status": "pending"
        }
        """
        // This has no subject, so it will be orphaned (missing subject).
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(largeJSON, to: dir.appendingPathComponent("large.json"))

        let result = try await sut.loadTasks(from: dir)

        let orphan = try XCTUnwrap(result.orphanedTasks.first)
        let cap = 100 * 1024
        XCTAssertLessThanOrEqual(orphan.rawJSON.utf8.count, cap,
            "rawJSON must be capped at 100 KB; got \(orphan.rawJSON.utf8.count) bytes")
    }

    func testOrphanedPath_errorMessageIsNotEmpty() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.malformedJSON, to: dir.appendingPathComponent("bad2.json"))

        let result = try await sut.loadTasks(from: dir)

        let orphan = try XCTUnwrap(result.orphanedTasks.first)
        XCTAssertFalse(orphan.errorMessage.isEmpty, "OrphanedTask must carry a non-empty error message")
    }

    // MARK: - Mixed Directory

    func testMixedDirectory_allThreeCategoriesPopulated() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }

        // Structured (has schema_version)
        write(Self.validEpicJSON, to: dir.appendingPathComponent("1.json"))
        write(Self.validStoryJSON, to: dir.appendingPathComponent("10.json"))

        // ClaudeTask (no schema_version, has id+subject)
        write(Self.claudeTaskJSON, to: dir.appendingPathComponent("42.json"))

        // Orphaned — invalid JSON
        write(Self.malformedJSON, to: dir.appendingPathComponent("bad.json"))

        // Orphaned — empty
        write("", to: dir.appendingPathComponent("empty.json"))

        // Excluded non-task files
        write(Self.settingsJSON, to: dir.appendingPathComponent("settings.json"))
        write(Self.configJSON, to: dir.appendingPathComponent("config.json"))

        let result = try await sut.loadTasks(from: dir)

        XCTAssertEqual(result.structuredTasks.count, 2, "Two structured tasks expected")
        XCTAssertEqual(result.claudeTasks.count, 1, "One ClaudeTask expected")
        XCTAssertEqual(result.orphanedTasks.count, 2, "Two orphaned tasks expected")
    }

    func testMixedDirectory_structuredTasksAreNumericallySorted() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.validStoryJSON, to: dir.appendingPathComponent("10.json"))
        write(Self.validEpicJSON, to: dir.appendingPathComponent("1.json"))

        let result = try await sut.loadTasks(from: dir)

        let ids = result.structuredTasks.map { $0.id }
        XCTAssertEqual(ids, ["1", "10"], "Structured tasks must be sorted numerically, not lexicographically")
    }

    func testMixedDirectory_nonTaskFilesAreExcluded() async throws {
        let dir = makeIsolatedDir()
        defer { cleanup(dir) }
        write(Self.claudeTaskJSON, to: dir.appendingPathComponent("42.json"))
        write(Self.settingsJSON, to: dir.appendingPathComponent("settings.json"))
        write(Self.configJSON, to: dir.appendingPathComponent("config.json"))

        let result = try await sut.loadTasks(from: dir)

        // Only 42.json is a task file — settings.json and config.json must be excluded.
        let total = result.structuredTasks.count + result.claudeTasks.count + result.orphanedTasks.count
        XCTAssertEqual(total, 1, "Only task JSON files should be parsed; settings/config must be excluded")
    }

    // MARK: - Private Helpers

    private func write(_ content: String, to url: URL) {
        try? content.data(using: .utf8)?.write(to: url)
    }

    private func makeIsolatedDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }
}
