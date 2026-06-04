import AppKit
import Foundation

struct RedactionRect {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let imagePath = arguments.first else {
    fputs("usage: redact-screenshot.swift <image.png> [mode]\n", stderr)
    exit(2)
}

let mode = arguments.dropFirst().first ?? "chrome"
let imageURL = URL(fileURLWithPath: imagePath)
guard let image = NSImage(contentsOf: imageURL),
      let tiff = image.tiffRepresentation,
      let sourceRep = NSBitmapImageRep(data: tiff) else {
    fputs("redact-screenshot.swift: could not read image at \(imagePath)\n", stderr)
    exit(1)
}

let pixelWidth = Double(sourceRep.pixelsWide)
let pixelHeight = Double(sourceRep.pixelsHigh)
let canvasSize = NSSize(width: pixelWidth, height: pixelHeight)

let chromeRects = [
    RedactionRect(x: 0.040, y: 0.104, width: 0.145, height: 0.030),
    RedactionRect(x: 0.040, y: 0.154, width: 0.145, height: 0.030),
    RedactionRect(x: 0.225, y: 0.046, width: 0.598, height: 0.034)
]

let workbenchRects = chromeRects + [
    RedactionRect(x: 0.214, y: 0.080, width: 0.780, height: 0.080)
]

let tokenRecordsRects = [
    RedactionRect(x: 0.600, y: 0.035, width: 0.335, height: 0.045),
    RedactionRect(x: 0.055, y: 0.102, width: 0.890, height: 0.068),
    RedactionRect(x: 0.085, y: 0.205, width: 0.330, height: 0.105)
]

let redactions: [RedactionRect]
switch mode {
case "workbench":
    redactions = workbenchRects
case "token":
    redactions = tokenRecordsRects
default:
    redactions = chromeRects
}

let output = NSImage(size: canvasSize)
output.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(
    in: NSRect(origin: .zero, size: canvasSize),
    from: .zero,
    operation: .copy,
    fraction: 1
)

for rect in redactions {
    let drawRect = NSRect(
        x: rect.x * pixelWidth,
        y: pixelHeight - ((rect.y + rect.height) * pixelHeight),
        width: rect.width * pixelWidth,
        height: rect.height * pixelHeight
    )
    NSColor(calibratedWhite: 0.085, alpha: 1).setFill()
    NSBezierPath(roundedRect: drawRect, xRadius: 10, yRadius: 10).fill()
}
output.unlockFocus()

guard let outputTiff = output.tiffRepresentation,
      let outputRep = NSBitmapImageRep(data: outputTiff),
      let png = outputRep.representation(using: .png, properties: [:]) else {
    fputs("redact-screenshot.swift: could not encode redacted PNG\n", stderr)
    exit(1)
}

try png.write(to: imageURL)
