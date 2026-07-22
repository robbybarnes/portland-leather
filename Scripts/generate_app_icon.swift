#!/usr/bin/env swift
// Generates the 1024px app icon: a cream serif "L" monogram on a cognac
// field. Uses only macOS system frameworks; no third-party dependencies.
import AppKit
import CoreGraphics

let pixels = 1024
// CoreGraphics requires a 32-bit RGBX layout for a device-RGB bitmap context.
// The unused byte is explicitly skipped, so the resulting image has no alpha.
let bytesPerRow = pixels * 4
var pixelsData = Data(count: bytesPerRow * pixels)
let image: CGImage = pixelsData.withUnsafeMutableBytes { bytes in
    guard let context = CGContext(
        data: bytes.baseAddress,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("Could not create RGB graphics context")
    }

    context.setFillColor(red: 0x8A / 255.0, green: 0x4B / 255.0,
                         blue: 0x2A / 255.0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))

    let serifDescriptor = NSFontDescriptor
        .preferredFontDescriptor(forTextStyle: .largeTitle)
        .withDesign(.serif) ?? NSFontDescriptor(name: "Georgia", size: 640)
    let font = NSFont(descriptor: serifDescriptor, size: 640)
        ?? NSFont.systemFont(ofSize: 640)
    let monogram = NSAttributedString(string: "L", attributes: [
        .font: font,
        .foregroundColor: NSColor(
            red: 0xF7 / 255.0,
            green: 0xF2 / 255.0,
            blue: 0xE9 / 255.0,
            alpha: 1),
    ])
    let monogramSize = monogram.size()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    monogram.draw(at: NSPoint(
        x: (CGFloat(pixels) - monogramSize.width) / 2,
        y: (CGFloat(pixels) - monogramSize.height) / 2))
    NSGraphicsContext.restoreGraphicsState()

    guard let image = context.makeImage() else {
        fatalError("Could not create image")
    }
    return image
}

let bitmap = NSBitmapImageRep(cgImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("PNG encode failed")
}
let output = URL(fileURLWithPath:
    "Leatherfolio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true)
try png.write(to: output)
print("Wrote \(output.path) (\(png.count) bytes)")
