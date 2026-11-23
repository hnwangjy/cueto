import Foundation
#if os(macOS)
import AppKit
#endif

/// Small sRGB palette, independent of the source artwork's color profile or HDR range.
struct ArtworkProgressPalette: Equatable {
    struct RGB: Equatable {
        let r: Double
        let g: Double
        let b: Double
        static let white = RGB(r: 1, g: 1, b: 1)
        static let black = RGB(r: 0, g: 0, b: 0)

        func mixed(with other: RGB, amount: Double) -> RGB {
            RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
        }
        var luminance: Double {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        func contrast(with other: RGB) -> Double {
            (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
        }
#if os(macOS)
        var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
#endif
    }

    let keyColor: RGB

    func track(isDark: Bool, interaction: Int = 0) -> RGB {
        let level = Double(min(max(interaction, 0), 2))
        let value = isDark ? 0.28 + 0.02 * level : 0.90 + 0.015 * level
        return RGB(r: value, g: value, b: value)
    }

    func fill(isDark: Bool, interaction: Int) -> RGB {
        let isBrightArtwork = keyColor.luminance >= 0.48
        let level = Double(min(max(interaction, 0), 2))
        let maxChannel = max(keyColor.r, keyColor.g, keyColor.b)
        let minChannel = min(keyColor.r, keyColor.g, keyColor.b)
        let neutral = RGB(r: maxChannel, g: maxChannel, b: maxChannel)
        let saturation = maxChannel > 0 ? (maxChannel - minChannel) / maxChannel : 0
        let saturationLimit = isBrightArtwork ? 0.48 : 0.68
        var color = saturation > saturationLimit
            ? keyColor.mixed(with: neutral, amount: 1 - saturationLimit / saturation) : keyColor
        if isBrightArtwork {
            // Move vivid yellows slightly toward gold before lowering brightness.
            if keyColor.g >= keyColor.r * 0.82, keyColor.g <= keyColor.r * 1.03,
               keyColor.b < keyColor.g * 0.72 {
                if isDark {
                    color = RGB(r: color.r, g: color.g - (color.g - color.b) * 0.17, b: color.b)
                } else {
                    // A warmer hue stays clean when yellow must be readable on a pale rail.
                    let apricot = RGB(r: 0.76, g: 0.40, b: 0.29)
                    color = apricot.mixed(with: color, amount: 0.07)
                }
            }
            if isDark { color = color.mixed(with: .black, amount: 0.16) }
            color = color.mixed(with: .white, amount: level * 0.025)
        } else {
            if isDark { color = color.mixed(with: .white, amount: 0.32) }
            color = color.mixed(with: .white, amount: level * 0.08)
        }
        let rail = track(isDark: isDark, interaction: interaction)
        let destination: RGB = isDark ? .white : .black
        let original = color
        // Keep every interaction state distinct from the rail, including very dark/bright covers.
        for step in 0...100 {
            color = original.mixed(with: destination, amount: Double(step) / 100)
            if color.contrast(with: rail) >= 3.5 { break }
        }
        return color
    }

#if os(macOS)
    static func extract(from image: NSImage) -> ArtworkProgressPalette? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else { return nil }
        struct Bucket {
            var count = 0
            var r = 0.0
            var g = 0.0
            var b = 0.0
            var weight = 0.0
        }
        var buckets: [Int: Bucket] = [:]
        var visible = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha >= 0.6 else { continue }
            visible += 1
            let r = min(Double(pixels[offset]) / 255 / alpha, 1)
            let g = min(Double(pixels[offset + 1]) / 255 / alpha, 1)
            let b = min(Double(pixels[offset + 2]) / 255 / alpha, 1)
            let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            let saturation = color.saturationComponent
            let brightness = color.brightnessComponent
            guard saturation >= 0.12, brightness >= 0.10 else { continue }
            // Group neighboring hues instead of averaging complementary colors into gray.
            let key = min(Int(color.hueComponent * 24), 23) * 16 + min(Int(saturation * 4), 3) * 4 + min(Int(brightness * 4), 3)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1
            bucket.r += r; bucket.g += g; bucket.b += b
            bucket.weight += 0.35 + saturation * 0.65
            buckets[key] = bucket
        }
        guard let winner = buckets.sorted(by: { $0.key < $1.key }).max(by: { $0.value.weight < $1.value.weight })?.value,
              winner.count >= max(4, Int(Double(visible) * 0.025)) else { return nil }
        let count = Double(winner.count)
        return ArtworkProgressPalette(keyColor: RGB(r: winner.r / count, g: winner.g / count, b: winner.b / count))
    }
#endif
}
