#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-app-icon.swift <output.icns>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let sourceURL = scriptURL.appendingPathComponent("Assets/AppIconSource.png")
let fileManager = FileManager.default
let iconsetURL = outputURL
    .deletingPathExtension()
    .appendingPathExtension("iconset")
let artworkScale: CGFloat = 0.85

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("missing app icon source image: \(sourceURL.path)\n", stderr)
    exit(1)
}

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func renderedIcon(size: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let sourceSize = sourceImage.size
    let padding = CGFloat(size) * (1 - artworkScale) / 2
    let destination = NSRect(
        x: padding,
        y: padding,
        width: CGFloat(size) - padding * 2,
        height: CGFloat(size) - padding * 2
    )
    let clipPath = NSBezierPath(
        roundedRect: destination,
        xRadius: destination.width * 0.218,
        yRadius: destination.height * 0.218
    )
    let sourceAspect = sourceSize.width / max(sourceSize.height, 1)
    let destinationAspect = destination.width / max(destination.height, 1)
    let sourceRect: NSRect
    if sourceAspect > destinationAspect {
        let width = sourceSize.height * destinationAspect
        sourceRect = NSRect(
            x: (sourceSize.width - width) / 2,
            y: 0,
            width: width,
            height: sourceSize.height
        )
    } else {
        let height = sourceSize.width / destinationAspect
        sourceRect = NSRect(
            x: 0,
            y: (sourceSize.height - height) / 2,
            width: sourceSize.width,
            height: height
        )
    }

    NSGraphicsContext.saveGraphicsState()
    clipPath.addClip()
    sourceImage.draw(
        in: destination,
        from: sourceRect,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for (name, size) in sizes {
    try renderedIcon(size: size).write(to: iconsetURL.appendingPathComponent(name), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}

try? fileManager.removeItem(at: iconsetURL)
