import XCTest
@testable import AgileMaestro

final class FileWatcherServiceTests: XCTestCase {

    // MARK: - Properties

    var sut: FileWatcherService!
    var tempDirectoryURL: URL!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        sut = FileWatcherService()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        sut.stop()
        sut = nil
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
        super.tearDown()
    }

    // MARK: - DirectorySnapshot Diff Tests

    func testSnapshotDiffDetectsAddedFile() throws {
        let snapshot1 = DirectorySnapshot(directory: tempDirectoryURL)

        let newFile = tempDirectoryURL.appendingPathComponent("task-1.json")
        try Data("{}".utf8).write(to: newFile)

        let snapshot2 = DirectorySnapshot(directory: tempDirectoryURL)
        let diff = snapshot2.diff(from: snapshot1)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertTrue(diff.added.contains("task-1.json"))
        XCTAssertTrue(diff.removed.isEmpty)
        XCTAssertTrue(diff.modified.isEmpty)
    }

    func testSnapshotDiffDetectsRemovedFile() throws {
        let file = tempDirectoryURL.appendingPathComponent("task-1.json")
        try Data("{}".utf8).write(to: file)

        let snapshot1 = DirectorySnapshot(directory: tempDirectoryURL)
        try FileManager.default.removeItem(at: file)
        let snapshot2 = DirectorySnapshot(directory: tempDirectoryURL)
        let diff = snapshot2.diff(from: snapshot1)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertTrue(diff.removed.contains("task-1.json"))
        XCTAssertTrue(diff.added.isEmpty)
    }

    func testSnapshotDiffReturnsNoChangesForIdenticalSnapshots() throws {
        let file = tempDirectoryURL.appendingPathComponent("task-1.json")
        try Data("{}".utf8).write(to: file)

        let snapshot1 = DirectorySnapshot(directory: tempDirectoryURL)
        let snapshot2 = DirectorySnapshot(directory: tempDirectoryURL)
        let diff = snapshot2.diff(from: snapshot1)

        XCTAssertFalse(diff.hasChanges)
    }

    func testSnapshotIgnoresNonJsonFiles() throws {
        let txtFile = tempDirectoryURL.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: txtFile)

        let snapshot = DirectorySnapshot(directory: tempDirectoryURL)
        XCTAssertTrue(snapshot.entries.isEmpty, "Non-JSON files should be ignored")
    }

    func testSnapshotHandlesUnreadableDirectory() {
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString)")
        let snapshot = DirectorySnapshot(directory: nonExistentURL)
        XCTAssertTrue(snapshot.entries.isEmpty)
    }

    // MARK: - FileWatcherService Lifecycle Tests

    func testPollingDetectsNewFile() throws {
        let expectation = expectation(description: "onChange called after file addition")
        expectation.expectedFulfillmentCount = 1

        sut.onChange = {
            expectation.fulfill()
        }
        sut.start(watching: tempDirectoryURL)

        // Write a JSON file after a brief delay to allow the watcher to initialise
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let newFile = self.tempDirectoryURL.appendingPathComponent("task-new.json")
            try? Data("""
            {"id":"1","subject":"Test"}
            """.utf8).write(to: newFile)
        }

        // Allow up to 6 seconds for the poll tick (3s interval) + debounce (0.5s) + margin
        wait(for: [expectation], timeout: 6.0)
    }

    func testStopPreventsSubsequentCallbacks() throws {
        // Use an actor-isolated counter to safely mutate across concurrent contexts
        actor CallbackCounter {
            var count = 0
            func increment() { count += 1 }
        }
        let counter = CallbackCounter()

        sut.onChange = {
            Task { await counter.increment() }
        }
        sut.start(watching: tempDirectoryURL)
        sut.stop()

        // Write a file after stop — callback must not be invoked
        let file = tempDirectoryURL.appendingPathComponent("after-stop.json")
        try Data("{}".utf8).write(to: file)

        // Wait longer than one poll cycle to confirm silence
        let silence = expectation(description: "No callback after stop")
        silence.isInverted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            Task {
                let count = await counter.count
                if count > 0 { silence.fulfill() }
            }
        }
        wait(for: [silence], timeout: 5.0)
        let finalCount = expectation(description: "Check count")
        Task {
            let count = await counter.count
            XCTAssertEqual(count, 0)
            finalCount.fulfill()
        }
        wait(for: [finalCount], timeout: 2.0)
    }

    func testCallbackDeliveredOnMainThread() throws {
        let expectation = expectation(description: "onChange on main thread")

        sut.onChange = {
            XCTAssertTrue(Thread.isMainThread, "onChange must be called on the main thread")
            expectation.fulfill()
        }
        sut.start(watching: tempDirectoryURL)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let file = self.tempDirectoryURL.appendingPathComponent("main-thread-test.json")
            try? Data("{}".utf8).write(to: file)
        }

        wait(for: [expectation], timeout: 6.0)
    }
}
