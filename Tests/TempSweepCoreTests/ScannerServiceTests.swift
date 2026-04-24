import XCTest
@testable import TempSweepCore

final class ScannerServiceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TempSweepTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testScanModeRootsFavorSafeUserLocations() {
        let home = URL(fileURLWithPath: "/tmp/tempsweep-home", isDirectory: true)
        let temp = URL(fileURLWithPath: "/tmp/tempsweep-temporary", isDirectory: true)

        XCTAssertEqual(
            ScanMode.safeUserTemps.rootURLs(homeDirectory: home, temporaryDirectory: temp).map(\.path),
            [
                "/tmp/tempsweep-temporary",
                "/tmp/tempsweep-home/Library/Caches",
                "/tmp/tempsweep-home/Library/Logs"
            ]
        )

        XCTAssertTrue(
            ScanMode.aggressive.rootURLs(homeDirectory: home, temporaryDirectory: temp).map(\.path)
                .contains("/tmp/tempsweep-home/Library/Saved Application State")
        )
        XCTAssertTrue(
            ScanMode.wholeScan.rootURLs(homeDirectory: home, temporaryDirectory: temp).map(\.path)
                .contains("/tmp/tempsweep-home")
        )
    }

    func testScannerGroupsCandidatesAndSkipsSymlinksAndPackages() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let root = tempRoot.appendingPathComponent("scan-root", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        let package = root.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

        let oldFile = nested.appendingPathComponent("old.tmp")
        let newFile = root.appendingPathComponent("fresh.log")
        let packagedFile = package.appendingPathComponent("inside.tmp")
        try Data(repeating: 1, count: 128).write(to: oldFile)
        try Data(repeating: 2, count: 64).write(to: newFile)
        try Data(repeating: 3, count: 256).write(to: packagedFile)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-172_800)], ofItemAtPath: oldFile.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: newFile.path)

        let symlink = root.appendingPathComponent("old-link.tmp")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: oldFile)

        let scanner = ScannerService(
            configuration: ScannerConfiguration(
                rootsProvider: { _ in [root] },
                now: { now },
                minimumRecommendedAge: 3_600,
                minimumCandidateSize: 0
            )
        )

        let report = scanner.scan(mode: .safeUserTemps)
        let candidates = report.groups.flatMap(\.candidates)

        XCTAssertEqual(candidates.map(\.url.lastPathComponent).sorted(), ["fresh.log", "old.tmp"])
        XCTAssertEqual(report.totalCount, 2)
        XCTAssertEqual(report.totalSize, 192)
        XCTAssertTrue(candidates.first { $0.url.lastPathComponent == oldFile.lastPathComponent }?.isRecommendedForDeletion == true)
        XCTAssertTrue(candidates.first { $0.url.lastPathComponent == newFile.lastPathComponent }?.isRecommendedForDeletion == false)
        XCTAssertFalse(candidates.contains { $0.url == symlink })
        XCTAssertFalse(candidates.contains { $0.url == packagedFile })
    }

    func testScannerRecordsUnreadableOrMissingRootsWithoutFailingScan() {
        let missingRoot = tempRoot.appendingPathComponent("missing", isDirectory: true)
        let scanner = ScannerService(
            configuration: ScannerConfiguration(rootsProvider: { _ in [missingRoot] }, minimumCandidateSize: 0)
        )

        let report = scanner.scan(mode: .safeUserTemps)

        XCTAssertTrue(report.groups.isEmpty)
        XCTAssertEqual(report.errors.count, 1)
        XCTAssertEqual(report.errors.first?.url, missingRoot)
    }

    func testWholeScanSkipsSystemCriticalDirectories() throws {
        let root = tempRoot.appendingPathComponent("whole-root", isDirectory: true)
        let systemDirectory = root.appendingPathComponent("System", isDirectory: true)
        try FileManager.default.createDirectory(at: systemDirectory, withIntermediateDirectories: true)

        let safeFile = root.appendingPathComponent("candidate.tmp")
        let skippedFile = systemDirectory.appendingPathComponent("must-not-appear.tmp")
        try Data(repeating: 1, count: 16).write(to: safeFile)
        try Data(repeating: 2, count: 16).write(to: skippedFile)

        let scanner = ScannerService(
            configuration: ScannerConfiguration(rootsProvider: { _ in [root] }, minimumCandidateSize: 0)
        )

        let names = scanner.scan(mode: .wholeScan)
            .groups
            .flatMap(\.candidates)
            .map(\.url.lastPathComponent)

        XCTAssertEqual(names, ["candidate.tmp"])
    }

    func testWholeScanOnlyIncludesTemporaryLookingFiles() throws {
        let root = tempRoot.appendingPathComponent("broad-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try Data(repeating: 1, count: 16).write(to: root.appendingPathComponent("keeper.pdf"))
        try Data(repeating: 2, count: 16).write(to: root.appendingPathComponent("session.tmp"))
        try Data(repeating: 3, count: 16).write(to: root.appendingPathComponent("debug.log"))

        let scanner = ScannerService(
            configuration: ScannerConfiguration(rootsProvider: { _ in [root] }, minimumCandidateSize: 0)
        )

        let names = scanner.scan(mode: .wholeScan)
            .groups
            .flatMap(\.candidates)
            .map(\.url.lastPathComponent)
            .sorted()

        XCTAssertEqual(names, ["debug.log", "session.tmp"])
    }

    func testScannerSkipsTinyFilesByDefault() throws {
        let root = tempRoot.appendingPathComponent("tiny-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try Data(repeating: 1, count: 10_000).write(to: root.appendingPathComponent("tiny.tmp"))
        try Data(repeating: 2, count: 1_100_000).write(to: root.appendingPathComponent("larger.tmp"))

        let scanner = ScannerService(
            configuration: ScannerConfiguration(rootsProvider: { _ in [root] })
        )

        let names = scanner.scan(mode: .safeUserTemps)
            .groups
            .flatMap(\.candidates)
            .map(\.url.lastPathComponent)

        XCTAssertEqual(names, ["larger.tmp"])
    }

    func testScannerReportsProgressFromStartToFinish() throws {
        let root = tempRoot.appendingPathComponent("progress-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 16).write(to: root.appendingPathComponent("one.tmp"))

        let scanner = ScannerService(
            configuration: ScannerConfiguration(rootsProvider: { _ in [root] }, minimumCandidateSize: 0)
        )
        var snapshots: [ScanProgress] = []

        _ = scanner.scan(mode: .safeUserTemps) { progress in
            snapshots.append(progress)
        }

        XCTAssertEqual(snapshots.first?.fractionComplete, 0)
        XCTAssertEqual(snapshots.last?.fractionComplete, 1)
        XCTAssertTrue(snapshots.contains { $0.status.contains("Scanning") })
    }

    func testSortOrderPlacesLargestGroupsAndFilesFirst() throws {
        let root = tempRoot.appendingPathComponent("sort-root", isDirectory: true)
        let cacheRoot = root.appendingPathComponent("Library/Caches", isDirectory: true)
        let logRoot = root.appendingPathComponent("Library/Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logRoot, withIntermediateDirectories: true)

        try Data(repeating: 1, count: 20).write(to: cacheRoot.appendingPathComponent("small.cache"))
        try Data(repeating: 1, count: 100).write(to: logRoot.appendingPathComponent("big.log"))
        try Data(repeating: 1, count: 60).write(to: logRoot.appendingPathComponent("medium.log"))

        let scanner = ScannerService(
            configuration: ScannerConfiguration(rootsProvider: { _ in [cacheRoot, logRoot] }, minimumCandidateSize: 0)
        )

        let sortedGroups = scanner.scan(mode: .safeUserTemps)
            .groups
            .sorted(using: .sizeDescending)

        XCTAssertEqual(sortedGroups.map(\.category), [.logs, .caches])
        XCTAssertEqual(sortedGroups.first?.candidates.map(\.url.lastPathComponent), ["big.log", "medium.log"])
    }
}
