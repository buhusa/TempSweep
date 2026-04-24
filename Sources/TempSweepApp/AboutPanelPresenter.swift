import AppKit
import Foundation
import TempSweepCore

enum AboutPanelPresenter {
    @MainActor
    static func show(info: TempSweepAboutInfo = .default) {
        let credits = NSMutableAttributedString()
        credits.append(line("Creator: ", value: info.creator))
        credits.append(NSAttributedString(string: "\n"))
        credits.append(line("Contact: ", value: info.contact))
        credits.append(NSAttributedString(string: "\n\n"))
        credits.append(
            NSAttributedString(
                string: info.summary,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        )

        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: info.appName,
                .version: "0.1.0",
                .applicationVersion: "1",
                .credits: credits
            ]
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func line(_ label: String, value: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: label,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
        )
        result.append(
            NSAttributedString(
                string: value,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.labelColor
                ]
            )
        )
        return result
    }
}
