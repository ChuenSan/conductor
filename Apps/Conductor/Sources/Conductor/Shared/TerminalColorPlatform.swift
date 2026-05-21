import AppKit
import SwiftUI

extension Color {
    var conductorHexRGB: String? {
        guard let converted = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int((converted.redComponent * 255).rounded())
        let green = Int((converted.greenComponent * 255).rounded())
        let blue = Int((converted.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
