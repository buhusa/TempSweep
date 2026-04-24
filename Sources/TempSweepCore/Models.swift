import Foundation

public enum ScanMode: String, CaseIterable, Identifiable, Sendable {
    case safeUserTemps
    case aggressive
    case wholeScan

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safeUserTemps:
            "Safe User Temps"
        case .aggressive:
            "Aggressive"
        case .wholeScan:
            "Whole Scan"
        }
    }

    public var caution: String? {
        switch self {
        case .safeUserTemps:
            nil
        case .aggressive:
            "Aggressive mode includes more user cache locations. Review selections before cleaning."
        case .wholeScan:
            "Whole Scan can be slow and may need Full Disk Access for protected folders."
        }
    }

    public func rootURLs(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> [URL] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let safeRoots = [
            temporaryDirectory,
            library.appendingPathComponent("Caches", isDirectory: true),
            library.appendingPathComponent("Logs", isDirectory: true)
        ]

        switch self {
        case .safeUserTemps:
            return safeRoots
        case .aggressive:
            return safeRoots + [
                library.appendingPathComponent("Saved Application State", isDirectory: true),
                library.appendingPathComponent("HTTPStorages", isDirectory: true),
                library.appendingPathComponent("WebKit", isDirectory: true)
            ]
        case .wholeScan:
            return [
                URL(fileURLWithPath: "/", isDirectory: true),
                URL(fileURLWithPath: "/Volumes", isDirectory: true),
                homeDirectory,
                temporaryDirectory,
                URL(fileURLWithPath: "/tmp", isDirectory: true),
                URL(fileURLWithPath: "/var/tmp", isDirectory: true)
            ]
        }
    }
}

public enum CandidateCategory: String, CaseIterable, Identifiable, Sendable {
    case temporaryFiles
    case caches
    case logs
    case savedApplicationState
    case webStorage
    case wholeDisk

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .temporaryFiles:
            "Temporary Files"
        case .caches:
            "Caches"
        case .logs:
            "Logs"
        case .savedApplicationState:
            "Saved Application State"
        case .webStorage:
            "Web Storage"
        case .wholeDisk:
            "Whole Scan Results"
        }
    }
}

public struct FileCandidate: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let modifiedAt: Date?
    public let category: CandidateCategory
    public let isRecommendedForDeletion: Bool

    public init(
        url: URL,
        size: Int64,
        modifiedAt: Date?,
        category: CandidateCategory,
        isRecommendedForDeletion: Bool
    ) {
        self.url = url
        self.size = size
        self.modifiedAt = modifiedAt
        self.category = category
        self.isRecommendedForDeletion = isRecommendedForDeletion
    }
}

public struct ScanResultGroup: Identifiable, Hashable, Sendable {
    public var id: String { "\(category.rawValue)|\(rootURL.path)" }
    public let category: CandidateCategory
    public let rootURL: URL
    public let candidates: [FileCandidate]

    public var title: String { category.displayName }
    public var totalSize: Int64 { candidates.reduce(0) { $0 + $1.size } }
    public var recommendedSize: Int64 {
        candidates.filter(\.isRecommendedForDeletion).reduce(0) { $0 + $1.size }
    }

    public init(category: CandidateCategory, rootURL: URL, candidates: [FileCandidate]) {
        self.category = category
        self.rootURL = rootURL
        self.candidates = candidates
    }
}

public struct ScanError: Identifiable, Hashable, Sendable {
    public var id: String { "\(url.path)|\(message)" }
    public let url: URL
    public let message: String

    public init(url: URL, message: String) {
        self.url = url
        self.message = message
    }
}

public struct ScanReport: Sendable {
    public let groups: [ScanResultGroup]
    public let errors: [ScanError]
    public let scannedAt: Date

    public var totalCount: Int { groups.reduce(0) { $0 + $1.candidates.count } }
    public var totalSize: Int64 { groups.reduce(0) { $0 + $1.totalSize } }
    public var recommendedCount: Int {
        groups.reduce(0) { total, group in
            total + group.candidates.filter(\.isRecommendedForDeletion).count
        }
    }
    public var recommendedSize: Int64 { groups.reduce(0) { $0 + $1.recommendedSize } }

    public init(groups: [ScanResultGroup], errors: [ScanError], scannedAt: Date) {
        self.groups = groups
        self.errors = errors
        self.scannedAt = scannedAt
    }
}

public struct ScanProgress: Equatable, Sendable {
    public let fractionComplete: Double
    public let status: String

    public init(fractionComplete: Double, status: String) {
        self.fractionComplete = min(max(fractionComplete, 0), 1)
        self.status = status
    }
}

public enum ResultSortOrder: String, CaseIterable, Identifiable, Sendable {
    case sizeDescending
    case nameAscending

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sizeDescending:
            "Biggest First"
        case .nameAscending:
            "Name"
        }
    }
}

public extension Array where Element == ScanResultGroup {
    func sorted(using sortOrder: ResultSortOrder) -> [ScanResultGroup] {
        switch sortOrder {
        case .sizeDescending:
            sorted {
                if $0.totalSize == $1.totalSize {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.totalSize > $1.totalSize
            }
            .map { group in
                ScanResultGroup(
                    category: group.category,
                    rootURL: group.rootURL,
                    candidates: group.candidates.sorted {
                        if $0.size == $1.size {
                            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
                        }
                        return $0.size > $1.size
                    }
                )
            }
        case .nameAscending:
            sorted {
                if $0.title == $1.title {
                    return $0.rootURL.path.localizedStandardCompare($1.rootURL.path) == .orderedAscending
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .map { group in
                ScanResultGroup(
                    category: group.category,
                    rootURL: group.rootURL,
                    candidates: group.candidates.sorted {
                        $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
                    }
                )
            }
        }
    }
}

public enum DeletionMode: String, CaseIterable, Identifiable, Sendable {
    case moveToTrash
    case permanentDelete

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .moveToTrash:
            "Move to Trash"
        case .permanentDelete:
            "Delete Permanently"
        }
    }
}

public struct CleanFailure: Identifiable, Hashable, Sendable {
    public var id: String { "\(url.path)|\(message)" }
    public let url: URL
    public let message: String

    public init(url: URL, message: String) {
        self.url = url
        self.message = message
    }
}

public struct CleanResult: Sendable {
    public let deletedCount: Int
    public let freedBytes: Int64
    public let failed: [CleanFailure]

    public init(deletedCount: Int, freedBytes: Int64, failed: [CleanFailure]) {
        self.deletedCount = deletedCount
        self.freedBytes = freedBytes
        self.failed = failed
    }
}
