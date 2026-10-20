// Draws the placeholder app icon, a camera lens on a dark tile, into Resources/AppIcon.icns.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let context = NSGraphicsContext.current?.cgContext else { return false }
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat(hex >> 16 & 255) / 255, CGFloat(hex >> 8 & 255) / 255,
                                                CGFloat(hex & 255) / 255, alpha])!
    }
    func gradient(_ colors: [CGColor], _ stops: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops)!
    }

    // The tile sits on Apple's icon grid: 824 pt with a soft shadow under it.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
    context.addPath(tilePath)
    context.setFillColor(color(0x101722))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    context.drawLinearGradient(gradient([color(0x2A3550), color(0x0E1420)], [0, 1]),
                               start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    func disc(_ radius: CGFloat, _ fill: (CGRect) -> Void) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        fill(rect)
        context.restoreGState()
    }

    // Lens barrel: a brushed metal ring, lit from the top.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.55))
    context.setFillColor(color(0x1A202C))
    context.fillEllipse(in: CGRect(x: center.x - 300, y: center.y - 300, width: 600, height: 600))
    context.restoreGState()
    disc(300) { rect in
        context.drawLinearGradient(gradient([color(0xC9D1DE), color(0x6B7487), color(0x2B3140)], [0, 0.45, 1]),
                                   start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    }
    disc(262) { rect in
        context.drawLinearGradient(gradient([color(0x0B0F17), color(0x232B3B)], [0, 1]),
                                   start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    }
    // Glass: deep blue with a violet edge, like coated optics.
    disc(220) { rect in
        context.drawRadialGradient(gradient([color(0x3B6BD6), color(0x1B2A6B), color(0x2A1450), color(0x05060C)], [0, 0.35, 0.7, 1]),
                                   startCenter: CGPoint(x: rect.midX - 40, y: rect.midY + 50), startRadius: 0,
                                   endCenter: center, endRadius: 220, options: [])
    }
    disc(92) { rect in
        context.drawRadialGradient(gradient([color(0x10131C), color(0x000000)], [0, 1]),
                                   startCenter: center, startRadius: 0, endCenter: center, endRadius: 92, options: [])
    }
    // Two reflections on the glass.
    context.setFillColor(color(0xFFFFFF, 0.55))
    context.fillEllipse(in: CGRect(x: 418, y: 590, width: 74, height: 52))
    context.setFillColor(color(0xFFFFFF, 0.22))
    context.fillEllipse(in: CGRect(x: 588, y: 410, width: 34, height: 24))

    // The live dot, top right, the same red as the menu's live badge.
    let dot = CGRect(x: 744, y: 744, width: 76, height: 76)
    context.saveGState()
    context.setShadow(offset: .zero, blur: 18, color: color(0xFF3B30, 0.6))
    context.setFillColor(color(0xFF3B30))
    context.fillEllipse(in: dot)
    context.restoreGState()
    return true
}

let fileManager = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Resources/AppIcon.icns")
