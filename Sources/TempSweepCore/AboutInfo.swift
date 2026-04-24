import Foundation

public struct TempSweepAboutInfo: Equatable, Sendable {
    public let appName: String
    public let summary: String
    public let creator: String
    public let contact: String

    public init(appName: String, summary: String, creator: String, contact: String) {
        self.appName = appName
        self.summary = summary
        self.creator = creator
        self.contact = contact
    }

    public static let `default` = TempSweepAboutInfo(
        appName: "TempSweep",
        summary: "A local, unsigned macOS cleaner for finding bigger temporary files and reviewing them before deletion.",
        creator: "buhussy",
        contact: "x.com/buhusa"
    )
}
