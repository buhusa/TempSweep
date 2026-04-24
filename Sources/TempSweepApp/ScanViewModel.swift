import Foundation
import TempSweepCore

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var scanMode: ScanMode = .safeUserTemps
    @Published var sortOrder: ResultSortOrder = .sizeDescending {
        didSet {
            updateSortedGroups()
        }
    }
    @Published private(set) var report = ScanReport(groups: [], errors: [], scannedAt: Date())
    @Published private(set) var sortedGroups: [ScanResultGroup] = []
    @Published private(set) var selectedIDs: Set<FileCandidate.ID> = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanProgress = ScanProgress(fractionComplete: 0, status: "Ready")
    @Published var cleanSummary: String?

    private let scanner: ScannerService
    private let cleaner: CleanerService

    init(
        scanner: ScannerService = ScannerService(),
        cleaner: CleanerService = CleanerService()
    ) {
        self.scanner = scanner
        self.cleaner = cleaner
    }

    var groups: [ScanResultGroup] { sortedGroups }
    var errors: [ScanError] { report.errors }
    var totalSize: Int64 { report.totalSize }
    var totalCount: Int { report.totalCount }

    var selectedCandidates: [FileCandidate] {
        groups.flatMap(\.candidates).filter { selectedIDs.contains($0.id) }
    }

    var selectedSize: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.size }
    }

    var selectedCount: Int { selectedCandidates.count }

    func scan() {
        guard !isScanning else {
            return
        }

        isScanning = true
        cleanSummary = nil
        scanProgress = ScanProgress(fractionComplete: 0, status: "Preparing \(scanMode.displayName)")

        let mode = scanMode
        let scanner = scanner
        Task {
            let nextReport = await Self.performScan(scanner: scanner, mode: mode) { [weak self] progress in
                Task { @MainActor in
                    self?.scanProgress = progress
                }
            }

            report = nextReport
            updateSortedGroups()
            selectedIDs = Set(
                nextReport.groups
                    .flatMap(\.candidates)
                    .filter(\.isRecommendedForDeletion)
                    .map(\.id)
            )
            scanProgress = ScanProgress(fractionComplete: 1, status: "Scan complete")
            isScanning = false
        }
    }

    func isSelected(_ candidate: FileCandidate) -> Bool {
        selectedIDs.contains(candidate.id)
    }

    func setSelected(_ candidate: FileCandidate, selected: Bool) {
        if selected {
            selectedIDs.insert(candidate.id)
        } else {
            selectedIDs.remove(candidate.id)
        }
    }

    func isGroupSelected(_ group: ScanResultGroup) -> Bool {
        !group.candidates.isEmpty && group.candidates.allSatisfy { selectedIDs.contains($0.id) }
    }

    func setGroupSelected(_ group: ScanResultGroup, selected: Bool) {
        for candidate in group.candidates {
            setSelected(candidate, selected: selected)
        }
    }

    func cleanSelected(mode: DeletionMode) {
        let attempted = selectedCandidates
        let result = cleaner.clean(attempted, mode: mode)
        let failedIDs = Set(result.failed.map { $0.url.path })
        let removedIDs = Set(attempted.map(\.id)).subtracting(failedIDs)

        selectedIDs.subtract(removedIDs)
        report = ScanReport(
            groups: report.groups.compactMap { group in
                let remaining = group.candidates.filter { !removedIDs.contains($0.id) }
                return remaining.isEmpty ? nil : ScanResultGroup(
                    category: group.category,
                    rootURL: group.rootURL,
                    candidates: remaining
                )
            },
            errors: report.errors + result.failed.map { ScanError(url: $0.url, message: $0.message) },
            scannedAt: report.scannedAt
        )
        updateSortedGroups()

        cleanSummary = "\(result.deletedCount) item\(result.deletedCount == 1 ? "" : "s") cleaned, \(TempSweepFormatters.bytes(result.freedBytes)) freed"
    }

    private func updateSortedGroups() {
        sortedGroups = report.groups.sorted(using: sortOrder)
    }

    private nonisolated static func performScan(
        scanner: ScannerService,
        mode: ScanMode,
        progressHandler: @escaping @Sendable (ScanProgress) -> Void
    ) async -> ScanReport {
        await Task.detached(priority: .userInitiated) {
            scanner.scan(mode: mode, progressHandler: progressHandler)
        }.value
    }
}
