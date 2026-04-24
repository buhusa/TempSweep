import XCTest
@testable import TempSweepCore

final class CleanerServiceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TempSweepCleanerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testPermanentDeleteRemovesSelectedFilesAndReportsFailures() throws {
        let removable = tempRoot.appendingPathComponent("remove.tmp")
        let missing = tempRoot.appendingPathComponent("already-gone.tmp")
        try Data("temporary".utf8).write(to: removable)

        let service = CleanerService()
        let result = service.clean(
            [
                FileCandidate(url: removable, size: 9, modifiedAt: Date(), category: .temporaryFiles, isRecommendedForDeletion: true),
                FileCandidate(url: missing, size: 1, modifiedAt: Date(), category: .temporaryFiles, isRecommendedForDeletion: true)
            ],
            mode: .permanentDelete
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: removable.path))
        XCTAssertEqual(result.deletedCount, 1)
        XCTAssertEqual(result.failed.count, 1)
        XCTAssertEqual(result.failed.first?.url, missing)
    }
}
