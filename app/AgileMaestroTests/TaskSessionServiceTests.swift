import XCTest
@testable import AgileMaestro

final class TaskSessionServiceTests: XCTestCase {

    // MARK: - Properties

    private var tempBaseDir: URL!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        tempBaseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        // Create 3 subdirectories with controlled modification dates
        let names = ["aaa", "bbb", "ccc"]
        let now = Date()
        let intervals: [TimeInterval] = [0, -60, -120]

        for (name, interval) in zip(names, intervals) {
            let url = tempBaseDir.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

            // Set modification date by writing a sentinel file with a known timestamp
            let sentinelURL = url.appendingPathComponent(".sentinel")
            let date = now.addingTimeInterval(interval)
            try? Data("".utf8).write(to: sentinelURL)
            try? FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: url.path
            )
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempBaseDir)
        tempBaseDir = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testReturnsMaxSessions() async throws {
        let sut = TaskSessionService(tasksRoot: tempBaseDir)
        let sessions = try await sut.getRecentSessions(maxSessions: 2)
        XCTAssertEqual(sessions.count, 2)
    }

    func testReturnsAllSessionsWhenUnderLimit() async throws {
        let sut = TaskSessionService(tasksRoot: tempBaseDir)
        let sessions = try await sut.getRecentSessions(maxSessions: 10)
        XCTAssertEqual(sessions.count, 3)
    }

    func testSortsByModificationDateDescending() async throws {
        let sut = TaskSessionService(tasksRoot: tempBaseDir)
        let sessions = try await sut.getRecentSessions(maxSessions: 10)

        guard sessions.count >= 2 else {
            XCTFail("Expected at least 2 sessions")
            return
        }

        for i in 0..<sessions.count - 1 {
            XCTAssertGreaterThanOrEqual(
                sessions[i].modifiedDate,
                sessions[i + 1].modifiedDate,
                "Sessions should be sorted by modifiedDate descending"
            )
        }
    }

    func testStableUUIDFromNonUUIDName() async throws {
        // The directory "aaa" is not a UUID — service should produce a deterministic UUID
        let sut1 = TaskSessionService(tasksRoot: tempBaseDir)
        let sut2 = TaskSessionService(tasksRoot: tempBaseDir)

        let sessions1 = try await sut1.getRecentSessions(maxSessions: 10)
        let sessions2 = try await sut2.getRecentSessions(maxSessions: 10)

        guard
            let first1 = sessions1.first(where: { $0.path.lastPathComponent == "aaa" }),
            let first2 = sessions2.first(where: { $0.path.lastPathComponent == "aaa" })
        else {
            XCTFail("Could not find 'aaa' session in results")
            return
        }

        XCTAssertEqual(first1.id, first2.id, "UUID for non-UUID directory name must be stable across calls")
    }

    func testNonExistentRootReturnsEmpty() async throws {
        let nonExistent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sut = TaskSessionService(tasksRoot: nonExistent)
        let sessions = try await sut.getRecentSessions(maxSessions: 5)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testUUIDDirectoryNameUsedDirectly() async throws {
        // Create a subdirectory with a valid UUID name
        let knownUUID = UUID()
        let uuidDir = tempBaseDir.appendingPathComponent(knownUUID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: uuidDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: uuidDir) }

        let sut = TaskSessionService(tasksRoot: tempBaseDir)
        let sessions = try await sut.getRecentSessions(maxSessions: 10)

        let found = sessions.first { $0.path.lastPathComponent == knownUUID.uuidString }
        XCTAssertNotNil(found, "Session for UUID-named directory should exist")
        XCTAssertEqual(found?.id, knownUUID, "Session ID should equal the directory name UUID")
    }
}
