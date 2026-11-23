import AppKit

@main
struct ArtworkProgressPaletteTests {
    static func main() {
        func image(_ color: NSColor, accent: NSColor? = nil) -> NSImage {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                bytesPerRow: 32 * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color.usingColorSpace(.sRGB)!.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            if let accent {
                context.setFillColor(accent.usingColorSpace(.sRGB)!.cgColor)
                context.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
            }
            return NSImage(cgImage: context.makeImage()!, size: NSSize(width: 32, height: 32))
        }
        assert(ArtworkProgressPalette.extract(from: image(.clear)) == nil)
        assert(ArtworkProgressPalette.extract(from: image(.white)) == nil)
        assert(ArtworkProgressPalette.extract(from: image(.gray)) == nil)
        let red = ArtworkProgressPalette.extract(from: image(.black, accent: NSColor(srgbRed: 0.85, green: 0.15, blue: 0.20, alpha: 1)))!
        assert(red.keyColor.r > red.keyColor.g * 2)
        assert(red.keyColor.r > red.keyColor.b * 2)
        let blue = ArtworkProgressPalette.extract(from: image(NSColor(srgbRed: 0.12, green: 0.35, blue: 0.9, alpha: 1)))!
        assert(blue.keyColor.b > blue.keyColor.r * 2)
        let colors = [red.keyColor, blue.keyColor, .white, .black,
                      .init(r: 1, g: 1, b: 0), .init(r: 0, g: 1, b: 0), .init(r: 0.08, g: 0.02, b: 0.04)]
        for key in colors {
            let palette = ArtworkProgressPalette(keyColor: key)
            for dark in [false, true] {
                for state in 0...2 {
                    let fill = palette.fill(isDark: dark, interaction: state)
                    let track = ArtworkProgressPalette.track(isDark: dark, interaction: state)
                    assert(fill.contrast(with: track) >= 3.5)
                    assert([fill.r, fill.g, fill.b].allSatisfy { $0.isFinite && (0...1).contains($0) })
                }
            }
        }
        // Contrast adjustments retain the representative hue rather than changing it to system blue.
        for dark in [false, true] {
            let fill = red.fill(isDark: dark, interaction: 0)
            assert(fill.r > fill.g && fill.r > fill.b)
        }
        print("Artwork palette extraction, transparency, hue, and all-state contrast tests passed")
    }
}
