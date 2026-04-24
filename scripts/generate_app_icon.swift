import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let iconset = root.appendingPathComponent("Sources/TempSweepApp/Resources/AppIcon.iconset", isDirectory: true)
let icns = root.appendingPathComponent("Sources/TempSweepApp/Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

struct IconSize {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var filename: String {
        scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png"
    }
}

let sizes = [
    IconSize(points: 16, scale: 1),
    IconSize(points: 16, scale: 2),
    IconSize(points: 32, scale: 1),
    IconSize(points: 32, scale: 2),
    IconSize(points: 128, scale: 1),
    IconSize(points: 128, scale: 2),
    IconSize(points: 256, scale: 1),
    IconSize(points: 256, scale: 2),
    IconSize(points: 512, scale: 1),
    IconSize(points: 512, scale: 2)
]

func drawIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let scale = CGFloat(size) / 1024
    let radius = 224 * scale
    let background = CGPath(
        roundedRect: rect.insetBy(dx: 42 * scale, dy: 42 * scale),
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )

    context.addPath(background)
    context.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(red: 0.02, green: 0.09, blue: 0.12, alpha: 1).cgColor,
            NSColor(red: 0.00, green: 0.42, blue: 0.48, alpha: 1).cgColor,
            NSColor(red: 0.47, green: 0.86, blue: 0.78, alpha: 1).cgColor
        ] as CFArray,
        locations: [0.0, 0.58, 1.0]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    context.setFillColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    context.fillEllipse(in: CGRect(x: 590 * scale, y: 612 * scale, width: 300 * scale, height: 300 * scale))

    context.setStrokeColor(NSColor.white.withAlphaComponent(0.94).cgColor)
    context.setLineWidth(74 * scale)
    context.setLineCap(.round)
    context.addArc(
        center: CGPoint(x: 516 * scale, y: 490 * scale),
        radius: 260 * scale,
        startAngle: CGFloat.pi * 1.08,
        endAngle: CGFloat.pi * 1.88,
        clockwise: false
    )
    context.strokePath()

    context.setStrokeColor(NSColor(red: 0.76, green: 1.0, blue: 0.95, alpha: 1).cgColor)
    context.setLineWidth(38 * scale)
    context.addArc(
        center: CGPoint(x: 516 * scale, y: 490 * scale),
        radius: 188 * scale,
        startAngle: CGFloat.pi * 1.06,
        endAngle: CGFloat.pi * 1.72,
        clockwise: false
    )
    context.strokePath()

    let handlePath = CGMutablePath()
    handlePath.move(to: CGPoint(x: 644 * scale, y: 652 * scale))
    handlePath.addLine(to: CGPoint(x: 806 * scale, y: 814 * scale))
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    context.setLineWidth(52 * scale)
    context.setLineCap(.round)
    context.addPath(handlePath)
    context.strokePath()

    context.setFillColor(NSColor(red: 0.98, green: 0.79, blue: 0.32, alpha: 1).cgColor)
    for shard in [
        CGRect(x: 206, y: 646, width: 74, height: 74),
        CGRect(x: 304, y: 750, width: 48, height: 48),
        CGRect(x: 196, y: 310, width: 56, height: 56),
        CGRect(x: 752, y: 294, width: 44, height: 44)
    ] {
        context.saveGState()
        context.translateBy(x: shard.midX * scale, y: shard.midY * scale)
        context.rotate(by: 0.28)
        context.fill(CGRect(
            x: -shard.width * scale / 2,
            y: -shard.height * scale / 2,
            width: shard.width * scale,
            height: shard.height * scale
        ))
        context.restoreGState()
    }

    context.resetClip()
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
    context.setLineWidth(3 * scale)
    context.addPath(background)
    context.strokePath()

    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "TempSweepIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render \(pixels)px icon."])
    }

    try png.write(to: url)
}

for size in sizes {
    let image = drawIcon(size: size.pixels)
    try writePNG(image, to: iconset.appendingPathComponent(size.filename), pixels: size.pixels)
}

try? FileManager.default.removeItem(at: icns)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "TempSweepIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed."])
}

print("Created \(icns.path)")
