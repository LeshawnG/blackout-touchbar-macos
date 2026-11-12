// Renders the Blackout app icon with AppKit/CoreGraphics (no dependencies) and packs it with iconutil.
//
//   swift tools/make_icon.swift <icns dir> <png dir>     (./build.sh icon does this)
//
// Design: a deep-blue tile with a few faint stars and a Touch Bar strip across the middle,
// whose keys fade from glowing blue to black: the bar going dark.
// Geometry is in 1024-px icon units on the macOS grid (824-px tile, 100-px margin).

import AppKit

let args = CommandLine.arguments
let icnsDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "Resources")
let pngDir = URL(fileURLWithPath: args.count > 2 ? args[2] : "docs")

func hex(_ s: String, _ alpha: CGFloat = 1) -> NSColor {
    let v = Int(s.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

func drawIcon(size: CGFloat) {
    let k = size / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: k, y: k)

    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    // Drop shadow under the tile.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.4)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    hex("#03060f").setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Deep-blue tile with a soft glow behind the lit end of the bar, and faint stars.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [hex("#16357a"), hex("#0a1838"), hex("#02040b")], atLocations: [0, 0.5, 1],
               colorSpace: .sRGB)!.draw(in: tile, angle: -90)
    NSGradient(colors: [hex("#3d7dff", 0.38), hex("#3d7dff", 0)])!
        .draw(fromCenter: NSPoint(x: 330, y: 512), radius: 0, toCenter: NSPoint(x: 330, y: 512), radius: 420, options: [])
    if size >= 128 {
        var seed: UInt64 = 0x5EED
        func random() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }
        for _ in 0..<46 {
            let x = 140 + random() * 744, y = 140 + random() * 744, r = 1.6 + random() * 3.2, a = 0.18 + random() * 0.5
            if abs(y - 512) < 120 { continue }   // keep the bar's band clear
            hex("#d6e4ff", a).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    // Thin light rim on the tile edge.
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
    rim.lineWidth = 4
    hex("#ffffff", 0.08).setStroke()
    rim.stroke()

    // The Touch Bar strip.
    let pill = NSRect(x: 162, y: 446, width: 700, height: 132)
    let pillPath = NSBezierPath(roundedRect: pill, xRadius: 66, yRadius: 66)
    hex("#010204").setFill()
    pillPath.fill()
    pillPath.lineWidth = size >= 64 ? 6 : 14
    hex("#3b4c74").setStroke()
    pillPath.stroke()

    // Keys fading from lit to dark.
    let keyW: CGFloat = 100, keyH: CGFloat = 70, gap: CGFloat = 24
    let levels: [CGFloat] = [1, 0.7, 0.32, 0.1, 0]
    let x0 = pill.minX + (pill.width - (CGFloat(levels.count) * keyW + CGFloat(levels.count - 1) * gap)) / 2
    for (i, level) in levels.enumerated() {
        let rect = NSRect(x: x0 + CGFloat(i) * (keyW + gap), y: pill.midY - keyH / 2, width: keyW, height: keyH)
        let key = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
        if level > 0 {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = hex("#4aa8ff", 0.95 * level)
            glow.shadowBlurRadius = 46
            glow.shadowOffset = .zero
            glow.set()
            hex("#3a8bff", level).setFill()
            key.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGradient(colors: [hex("#b4ecff", level), hex("#3a8bff", level)])!.draw(in: key, angle: -90)
        } else {
            key.lineWidth = size >= 64 ? 4 : 10
            hex("#1c2640").setStroke()
            key.stroke()
        }
    }
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! fm.createDirectory(at: icnsDir, withIntermediateDirectories: true)
try! fm.createDirectory(at: pngDir, withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsDir.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
try! png(size: 1024).write(to: pngDir.appendingPathComponent("icon.png"))
try? fm.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote \(icnsDir.path)/AppIcon.icns and \(pngDir.path)/icon.png" : "iconutil failed")
