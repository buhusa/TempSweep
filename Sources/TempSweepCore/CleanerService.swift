import Foundation

public final class CleanerService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func clean(_ candidates: [FileCandidate], mode: DeletionMode) -> CleanResult {
        var deletedCount = 0
        var freedBytes: Int64 = 0
        var failures: [CleanFailure] = []

        for candidate in candidates {
            guard fileManager.fileExists(atPath: candidate.url.path) else {
                failures.append(CleanFailure(url: candidate.url, message: "File no longer exists."))
                continue
            }

            do {
                switch mode {
                case .moveToTrash:
                    var trashedURL: NSURL?
                    try fileManager.trashItem(
                        at: candidate.url,
                        resultingItemURL: &trashedURL
                    )
                case .permanentDelete:
                    try fileManager.removeItem(at: candidate.url)
                }

                deletedCount += 1
                freedBytes += candidate.size
            } catch {
                failures.append(CleanFailure(url: candidate.url, message: error.localizedDescription))
            }
        }

        return CleanResult(deletedCount: deletedCount, freedBytes: freedBytes, failed: failures)
    }
}
