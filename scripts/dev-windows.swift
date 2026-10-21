// Independent evidence for the dev instance: what the window server says about its windows and the screen.
//
//   swift scripts/dev-windows.swift windows PID     one line per window of PID: number, layer, bounds, onscreen
//   swift scripts/dev-windows.swift visible PID     exit 1 if a window of PID with a title or size sits at or above the desktop level
//   swift scripts/dev-windows.swift diff A.png B.png  share of pixels that differ, ignoring the menu bar strip
import CoreGraphics
import Foundation
import ImageIO

func windows(of pid: Int32) -> [[String: Any]] {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
}

func describe(_ window: [String: Any]) -> String {
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let box = ["X", "Y", "Width", "Height"].map { String(describing: bounds[$0] ?? "?") }.joined(separator: " ")
    return "number=\(window[kCGWindowNumber as String] ?? "?") layer=\(window[kCGWindowLayer as String] ?? "?") "
        + "onscreen=\(window[kCGWindowIsOnscreen as String] ?? false) bounds=[\(box)] name=\(window[kCGWindowName as String] ?? "")"
}

func pixels(_ path: String) -> (width: Int, height: Int, bytes: [UInt8])? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (width, height, bytes)
}

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else { fputs("windows|visible PID, or diff A.png B.png\n", stderr); exit(2) }
switch command {
case "windows":
    guard let pid = arguments.dropFirst().first.flatMap({ Int32($0) }) else { exit(2) }
    for window in windows(of: pid) { print(describe(window)) }
case "visible":
    guard let pid = arguments.dropFirst().first.flatMap({ Int32($0) }) else { exit(2) }
    let desktop = Int(CGWindowLevelForKey(.desktopWindow))
    // Windows the app owns with real content: titled or larger than a status item. Anything below the desktop level hides behind the wallpaper.
    let shown = windows(of: pid).filter {
        let layer = $0[kCGWindowLayer as String] as? Int ?? 0
        let bounds = $0[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let height = bounds["Height"] as? Double ?? 0
        return layer >= desktop && height > 30 && ($0[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }
    for window in shown { print("VISIBLE \(describe(window))") }
    exit(shown.isEmpty ? 0 : 1)
case "diff":
    let paths = Array(arguments.dropFirst())
    guard paths.count == 2, let a = pixels(paths[0]), let b = pixels(paths[1]), a.width == b.width, a.height == b.height else {
        fputs("diff needs two PNGs of one size\n", stderr); exit(2)
    }
    // Skip the top 80 px, where the menu bar clock changes by itself.
    var changed = 0, total = 0
    for y in 80..<a.height {
        for x in 0..<a.width {
            let i = (y * a.width + x) * 4
            total += 1
            if abs(Int(a.bytes[i]) - Int(b.bytes[i])) > 8 || abs(Int(a.bytes[i + 1]) - Int(b.bytes[i + 1])) > 8
                || abs(Int(a.bytes[i + 2]) - Int(b.bytes[i + 2])) > 8 { changed += 1 }
        }
    }
    print(String(format: "%.4f", Double(changed) / Double(max(total, 1))))
default:
    exit(2)
}
