import XCTest
@testable import AgileMaestro

final class BackupServiceTests: XCTestCase {

    // MARK: - Properties

    var sut: BackupService!
    var sourceTempDirectoryURL: URL!
    var destinationTempDirectoryURL: URL!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        sut = BackupService()

        let base = FileManager.default.temporaryDirectory
        sourceTempDirectoryURL = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        destinationTempDirectoryURL = base.appendingPathComponent(UUID().uuidString, isDirectory: true)

        try? FileManager.default.createDirectory(at: sourceTempDirectoryURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: destinationTempDirectoryURL, withIntermediateDirectories: true)

        // Populate source with 2 JSON files
        writeFile("task-1.json", content: #"{"id":"1"}"#, to: sourceTempDirectoryURL)
        writeFile("task-2.json", content: #"{"id":"2"}"#, to: sourceTempDirectoryURL)
    }

    override func tearDown() {
        sut = nil
        try? FileManager.default.removeItem(at: sourceTempDirectoryURL)
        try? FileManager.default.removeItem(at: destinationTempDirectoryURL)
        sourceTempDirectoryURL = nil
        destinationTempDirectoryURL = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func writeFile(_ name: String, content: String, to directory: URL) {
        let url = directory.appendingPathComponent(name)
        try? Data(content.utf8).write(to: url)
    }

    private func jsonFilesInDestination() throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: destinationTempDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { $0.pathExtension == "json" }
            .map(\.lastPathComponent)
            .sorted()
    }

    // MARK: - Tests

    func testCopiesAllJsonFiles() async throws {
        try await sut.performBackup(from: sourceTempDirectoryURL, to: destinationTempDirectoryURL)

        let files = try jsonFilesInDestination()
        XCTAssertEqual(files, ["task-1.json", "task-2.json"])
    }

    func testAdditiveBehavior() async throws {
        // First backup: 2 files
        try await sut.performBackup(from: sourceTempDirectoryURL, to: destinationTempDirectoryURL)

        // Add a 3rd file to source
        writeFile("task-3.json", content: #"{"id":"3"}"#, to: sourceTempDirectoryURL)

        // Second backup: destination should now have 3 files (original 2 not deleted)
        try await sut.performBackup(from: sourceTempDirectoryURL, to: destinationTempDirectoryURL)

        let files = try jsonFilesInDestination()
        XCTAssertEqual(files, ["task-1.json", "task-2.json", "task-3.json"])
    }

    func testIgnoresNonJsonFilesInSource() async throws {
        // Add a non-JSON file to source
        writeFile("readme.txt", content: "hello", to: sourceTempDirectoryURL)

        try await sut.performBackup(from: sourceTempDirectoryURL, to: destinationTempDirectoryURL)

        let files = try jsonFilesInDestination()
        // Only the 2 original JSON files should be present
        XCTAssertEqual(files, ["task-1.json", "task-2.json"])
    }

    func testCreatesDestinationDirectoryIfAbsent() async throws {
        // Remove the destination so BackupService must create it
        try FileManager.default.removeItem(at: destinationTempDirectoryURL)

        try await sut.performBackup(from: sourceTempDirectoryURL, to: destinationTempDirectoryURL)

        let exists = FileManager.default.fileExists(atPath: destinationTempDirectoryURL.path)
        XCTAssertTrue(exists, "BackupService should create the destination directory")

        let files = try jsonFilesInDestination()
        XCTAssertEqual(files, ["task-1.json", "task-2.json"])
    }
}
