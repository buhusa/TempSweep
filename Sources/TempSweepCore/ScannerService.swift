import Foundation

public struct ScannerConfiguration: Sendable {
    public let rootsProvider: @Sendable (ScanMode) -> [URL]
    public let now: @Sendable () -> Date
    public let minimumRecommendedAge: TimeInterval
    public let minimumCandidateSize: Int64

    public init(
        rootsProvider: @escaping @Sendable (ScanMode) -> [URL] = { mode in mode.rootURLs() },
        now: @escaping @Sendable () -> Date = Date.init,
        minimumRecommendedAge: TimeInterval = 3_600,
        minimumCandidateSize: Int64 = 1_000_000
    ) {
        self.rootsProvider = rootsProvider
        self.now = now
        self.minimumRecommendedAge = minimumRecommendedAge
        self.minimumCandidateSize = minimumCandidateSize
    }
}

public final class ScannerService: @unchecked Sendable {
    private let configuration: ScannerConfiguration
    private let fileManager: FileManager

    public init(
        configuration: ScannerConfiguration = ScannerConfiguration(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    public func scan(
        mode: ScanMode,
        progressHandler: ((ScanProgress) -> Void)? = nil
    ) -> ScanReport {
        let scannedAt = configuration.now()
        var candidates: [FileCandidate] = []
        var errors: [ScanError] = []
        let roots = uniqueExistingOrder(configuration.rootsProvider(mode))
        let rootCount = max(roots.count, 1)

        progressHandler?(ScanProgress(fractionComplete: 0, status: "Preparing \(mode.displayName)"))

        for (rootIndex, root) in roots.enumerated() {
            let rootBaseProgress = Double(rootIndex) / Double(rootCount)
            let rootProgressSpan = 1.0 / Double(rootCount)
            progressHandler?(
                ScanProgress(
                    fractionComplete: rootBaseProgress,
                    status: "Scanning \(displayName(for: root))"
                )
            )

            guard isDirectory(root) else {
                errors.append(ScanError(url: root, message: "Folder is missing or not readable."))
                progressHandler?(
                    ScanProgress(
                        fractionComplete: Double(rootIndex + 1) / Double(rootCount),
                        status: "Skipped \(displayName(for: root))"
                    )
                )
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isPackageKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsPackageDescendants],
                errorHandler: { url, error in
                    errors.append(ScanError(url: url, message: error.localizedDescription))
                    return true
                }
            ) else {
                errors.append(ScanError(url: root, message: "Folder could not be scanned."))
                progressHandler?(
                    ScanProgress(
                        fractionComplete: Double(rootIndex + 1) / Double(rootCount),
                        status: "Skipped \(displayName(for: root))"
                    )
                )
                continue
            }

            var scannedItemsInRoot = 0
            while let item = enumerator.nextObject() as? URL {
                scannedItemsInRoot += 1
                if scannedItemsInRoot == 1 || scannedItemsInRoot.isMultiple(of: 500) {
                    let withinRoot = min(0.92, Double(scannedItemsInRoot) / Double(scannedItemsInRoot + 200))
                    progressHandler?(
                        ScanProgress(
                            fractionComplete: rootBaseProgress + (withinRoot * rootProgressSpan),
                            status: "Scanning \(displayName(for: root))"
                        )
                    )
                }

                do {
                    let values = try item.resourceValues(forKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .isPackageKey,
                        .fileSizeKey,
                        .contentModificationDateKey
                    ])

                    if values.isSymbolicLink == true {
                        if values.isDirectory == true {
                            enumerator.skipDescendants()
                        }
                        continue
                    }

                    if values.isDirectory == true && shouldSkipDirectory(item) {
                        enumerator.skipDescendants()
                        continue
                    }

                    if values.isPackage == true {
                        enumerator.skipDescendants()
                        continue
                    }

                    guard values.isRegularFile == true else {
                        continue
                    }

                    if mode == .wholeScan && !isTemporaryLookingFile(item) {
                        continue
                    }

                    let modifiedAt = values.contentModificationDate
                    let age = modifiedAt.map { scannedAt.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
                    let size = Int64(values.fileSize ?? 0)
                    guard size >= configuration.minimumCandidateSize else {
                        continue
                    }

                    candidates.append(
                        FileCandidate(
                            url: item,
                            size: size,
                            modifiedAt: modifiedAt,
                            category: category(for: item, root: root, mode: mode),
                            isRecommendedForDeletion: age >= configuration.minimumRecommendedAge
                        )
                    )
                } catch {
                    errors.append(ScanError(url: item, message: error.localizedDescription))
                }
            }

            progressHandler?(
                ScanProgress(
                    fractionComplete: Double(rootIndex + 1) / Double(rootCount),
                    status: "Finished \(displayName(for: root))"
                )
            )
        }

        progressHandler?(ScanProgress(fractionComplete: 1, status: "Scan complete"))

        return ScanReport(
            groups: groupedCandidates(candidates, roots: roots),
            errors: errors.sorted { $0.url.path < $1.url.path },
            scannedAt: scannedAt
        )
    }

    private func uniqueExistingOrder(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let key = url.standardizedFileURL.path
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func displayName(for url: URL) -> String {
        if url.path == "/" {
            return "Macintosh HD"
        }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    private func groupedCandidates(_ candidates: [FileCandidate], roots: [URL]) -> [ScanResultGroup] {
        let grouped = Dictionary(grouping: candidates) { candidate in
            GroupKey(category: candidate.category, rootURL: root(for: candidate.url, roots: roots))
        }

        return grouped.map { key, values in
            ScanResultGroup(
                category: key.category,
                rootURL: key.rootURL,
                candidates: values.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            )
        }
        .sorted {
            if $0.category.displayName == $1.category.displayName {
                return $0.rootURL.path.localizedStandardCompare($1.rootURL.path) == .orderedAscending
            }
            return $0.category.displayName < $1.category.displayName
        }
    }

    private func root(for url: URL, roots: [URL]) -> URL {
        roots
            .filter { url.path.hasPrefix($0.path) }
            .max { $0.path.count < $1.path.count }
            ?? url.deletingLastPathComponent()
    }

    private func shouldSkipDirectory(_ url: URL) -> Bool {
        let protectedNames: Set<String> = [
            "Applications",
            "Library",
            "System",
            "bin",
            "cores",
            "dev",
            "etc",
            "opt",
            "private",
            "sbin",
            "usr"
        ]
        let name = url.lastPathComponent
        if protectedNames.contains(name) || name.hasSuffix(".app") {
            return true
        }
        return name == ".git" || name == ".Trash" || name == "node_modules"
    }

    private func isTemporaryLookingFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let temporaryExtensions: Set<String> = [
            "bak",
            "cache",
            "crash",
            "download",
            "log",
            "old",
            "part",
            "swap",
            "temp",
            "tmp"
        ]

        if temporaryExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        return name.contains("cache")
            || name.contains("crash")
            || name.contains("temp")
            || name.contains("tmp")
    }

    private func category(for url: URL, root: URL, mode: ScanMode) -> CandidateCategory {
        let path = url.path
        if path.contains("/Library/Caches/") || root.lastPathComponent == "Caches" {
            return .caches
        }
        if path.contains("/Library/Logs/") || root.lastPathComponent == "Logs" {
            return .logs
        }
        if path.contains("/Saved Application State/") || root.lastPathComponent == "Saved Application State" {
            return .savedApplicationState
        }
        if path.contains("/HTTPStorages/") || path.contains("/WebKit/") {
            return .webStorage
        }
        return mode == .wholeScan ? .wholeDisk : .temporaryFiles
    }
}

private struct GroupKey: Hashable {
    let category: CandidateCategory
    let rootURL: URL
}
