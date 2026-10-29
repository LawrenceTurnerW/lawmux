#!/usr/bin/env bash
# Regenerate lawmux's app icon from scripts/lawmux-app-icon-glyph.png (a black
# glyph on a transparent background) into the upstream icon assets:
#
#   Assets.xcassets/AppIcon.appiconset/*.png   Finder, Launchpad, the Dock when quit
#   Assets.xcassets/AppIconLight.imageset      Dock icon at runtime, light
#   Assets.xcassets/AppIconDark.imageset       Dock icon at runtime, dark
#
# The light icon is the black glyph on a light rounded square; the dark one is
# the same glyph in white on a dark square. Overwriting the upstream PNGs keeps
# every code path that loads them by name unchanged. If an upstream sync
# conflicts on these files, take either side and rerun this script.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

GLYPH="scripts/lawmux-app-icon-glyph.png"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/make.swift" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
let glyphURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])

guard let source = NSImage(contentsOf: glyphURL),
      let glyph = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot read \(glyphURL.path)")
}

// Crop to the glyph's opaque pixels so the layout does not depend on padding.
func opaqueBounds(_ image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h { for x in 0..<w where data[y * w + x] > 8 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    // Rows in the bitmap run top-down; CGImage cropping is top-down as well.
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}
let cropped = glyph.cropping(to: opaqueBounds(glyph))!

struct Style {
    let top: NSColor, bottom: NSColor, ink: NSColor, rim: NSColor
}
let light = Style(top: NSColor(white: 1.0, alpha: 1), bottom: NSColor(white: 0.90, alpha: 1),
                  ink: NSColor(white: 0.07, alpha: 1), rim: NSColor(white: 0, alpha: 0.10))
let dark = Style(top: NSColor(white: 0.21, alpha: 1), bottom: NSColor(white: 0.08, alpha: 1),
                 ink: NSColor(white: 0.96, alpha: 1), rim: NSColor(white: 1, alpha: 0.12))

// macOS icon grid: an 824pt rounded square centred on a 1024pt canvas.
func render(_ style: Style, size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    gc.imageInterpolation = .high
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    ctx.scaleBy(x: s, y: s)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor(white: 0, alpha: 0.30).cgColor)
    ctx.addPath(path); ctx.setFillColor(style.bottom.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [style.top.cgColor, style.bottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // The glyph is tall and narrow: fit its height inside the square's padding.
    let glyphHeight: CGFloat = 720
    let glyphWidth = glyphHeight * CGFloat(cropped.width) / CGFloat(cropped.height)
    let glyphRect = CGRect(x: 512 - glyphWidth / 2, y: 512 - glyphHeight / 2, width: glyphWidth, height: glyphHeight)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.draw(cropped, in: glyphRect)
    ctx.setBlendMode(.sourceIn)
    ctx.setFillColor(style.ink.cgColor)
    ctx.fill(glyphRect)
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    ctx.addPath(path); ctx.setStrokeColor(style.rim.cgColor); ctx.setLineWidth(2); ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ name: String) {
    try! data.write(to: outDir.appendingPathComponent(name))
}

let iconset = outDir.appendingPathComponent("AppIcon.appiconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "\(base)" : "\(base)@2x"
        write(render(light, size: base * scale), "AppIcon.appiconset/\(name).png")
        write(render(dark, size: base * scale), "AppIcon.appiconset/\(name)_dark.png")
    }
}
write(render(light, size: 1024), "AppIconLight.png")
write(render(dark, size: 1024), "AppIconDark.png")
SWIFT

swiftc -O "$WORK/make.swift" -o "$WORK/make"
"$WORK/make" "$GLYPH" "$WORK"

cp "$WORK"/AppIcon.appiconset/*.png Assets.xcassets/AppIcon.appiconset/
cp "$WORK/AppIconLight.png" Assets.xcassets/AppIconLight.imageset/AppIconLight.png
cp "$WORK/AppIconDark.png" Assets.xcassets/AppIconDark.imageset/AppIconDark.png
echo "==> Updated AppIcon, AppIconLight and AppIconDark from $GLYPH"
