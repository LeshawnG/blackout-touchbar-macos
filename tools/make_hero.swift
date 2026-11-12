// Draws docs/hero.png: Touch Bar On, Touch Bar Off and Touch Bar Peek, with each shortcut.
//
//   screencapture -b /tmp/bar.png              # capture the lit Touch Bar
//   swift tools/make_hero.swift /tmp/bar.png docs/hero.png
//
// Only the Control Strip (right-hand end) of the capture is used; the rest of the bar is
// drawn black, so nothing from whatever app was in front ends up in the picture.
//
// Layout: equal outer margins on all sides; in each row the keycaps, the two lines of text and
// the Touch Bar share one centre line. Text is placed with CoreText metrics (cap height and
// ink bounds) rather than line boxes, so it sits optically centred.

import AppKit
import CoreText

let args = CommandLine.arguments
guard args.count == 3, let capture = NSImage(contentsOfFile: args[1]),
      let captureCG = capture.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: swift tools/make_hero.swift <touch bar capture.png> <out.png>")
    exit(2)
}

func hex(_ s: String, _ alpha: CGFloat = 1) -> NSColor {
    let v = Int(s.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

// Find where the Control Strip starts: scanning from the right, the first run of 30 black columns.
func controlStripStart(_ image: CGImage) -> Int {
    let w = image.width, h = image.height
    var buffer = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    func columnIsBlack(_ x: Int) -> Bool {
        (0..<h).allSatisfy { y in let i = (y * w + x) * 4; return max(buffer[i], buffer[i + 1], buffer[i + 2]) < 12 }
    }
    var x = w - 1, run = 0
    while x > 0 {
        run = columnIsBlack(x) ? run + 1 : 0
        if run >= 30 { return x + run - 8 }
        x -= 1
    }
    return 0
}
let stripStart = controlStripStart(captureCG)
let controlStrip = captureCG.cropping(to: CGRect(x: stripStart, y: 0, width: captureCG.width - stripStart, height: captureCG.height))!

// MARK: Canvas

let W: CGFloat = 1800, H: CGFloat = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext
cg.textMatrix = .identity

// MARK: Text helpers (CoreText)

struct Line {
    let line: CTLine
    let font: NSFont
    init(_ s: String, _ font: NSFont, _ color: NSColor) {
        self.font = font
        line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color]))
    }
    var width: CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }
    var ink: CGRect {                                     // relative to the baseline origin
        cg.textPosition = .zero   // CTLineGetImageBounds includes the context's current text position
        return CTLineGetImageBounds(line, cg)
    }
    func draw(x: CGFloat, baseline: CGFloat) {
        cg.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, cg)
    }
    /// Centre the visible glyphs on a point (for symbols in keycaps and badges).
    func drawInkCentered(at c: CGPoint) {
        let i = ink
        draw(x: c.x - i.midX, baseline: c.y - i.midY)
    }
}

/// SF Symbols' "timer" glyph, drawn white at about `size` points tall.
func timerSymbol(size: CGFloat) -> NSImage? {
    guard let base = NSImage(systemSymbolName: "timer", accessibilityDescription: "timer")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size * 0.82, weight: .bold)) else { return nil }
    return NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

// MARK: Layout

let margin: CGFloat = 72
let capSize: CGFloat = 62, capGap: CGFloat = 10, capRadius: CGFloat = 13
let capsWidth = 3 * capSize + 2 * capGap
let gapCapsToText: CGFloat = 30, gapTextToBar: CGFloat = 56
let bezel: CGFloat = 10
let titleFont = NSFont.systemFont(ofSize: 34, weight: .semibold)
let noteFont = NSFont.systemFont(ofSize: 22, weight: .regular)
let titleNoteGap: CGFloat = 14   // between the title's baseline and the note's cap top

let rows: [(keys: [String], title: String, note: String, lit: Bool)] = [
    (["⌥", "⌘", "0"], "Touch Bar On", "the normal Touch Bar", true),
    (["⌥", "⌘", "−"], "Touch Bar Off", "panel powered down", false),
    (["⌥", "⌘", "+"], "Touch Bar Peek", "auto-off in 5 s", true),
]

let textWidth = rows.map { max(Line($0.title, titleFont, .white).width, Line($0.note, noteFont, .white).width) }.max()!
let textX = margin + capsWidth + gapCapsToText
let barX = textX + textWidth + gapTextToBar + bezel
let barWidth = W - margin - bezel - barX
let barHeight = barWidth * CGFloat(captureCG.height) / CGFloat(captureCG.width)

// Rows evenly spaced, the block centred vertically; the middle row sits on the canvas centre.
let rowPitch: CGFloat = 182
let centres = (0..<rows.count).map { H / 2 + CGFloat(rows.count / 2 - $0) * rowPitch }

// MARK: Background card, in the icon's deep blue

NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: W, height: H), xRadius: 40, yRadius: 40).addClip()
NSGradient(colors: [hex("#132c66"), hex("#0a1838"), hex("#03060f")], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// MARK: Rows

for (row, mid) in zip(rows, centres) {
    // Keycaps
    for (i, key) in row.keys.enumerated() {
        let r = NSRect(x: margin + CGFloat(i) * (capSize + capGap), y: mid - capSize / 2, width: capSize, height: capSize)
        let cap = NSBezierPath(roundedRect: r, xRadius: capRadius, yRadius: capRadius)
        hex("#1a2338").setFill()
        cap.fill()
        cap.lineWidth = 2
        hex("#3b4c74").setStroke()
        cap.stroke()
        Line(key, NSFont.systemFont(ofSize: 30, weight: .semibold), .white).drawInkCentered(at: CGPoint(x: r.midX, y: r.midY))
    }

    // Title + note, centred as a block on the row's centre line (cap top of title to baseline of note).
    let titleCap = titleFont.capHeight, noteCap = noteFont.capHeight
    let block = titleCap + titleNoteGap + noteCap
    let noteBaseline = mid - block / 2
    let titleBaseline = noteBaseline + noteCap + titleNoteGap
    Line(row.title, titleFont, .white).draw(x: textX, baseline: titleBaseline)
    Line(row.note, noteFont, hex("#9fb3da")).draw(x: textX, baseline: noteBaseline)

    // The Touch Bar: bezel, black panel, and the Control Strip when lit.
    let bar = NSRect(x: barX, y: mid - barHeight / 2, width: barWidth, height: barHeight)
    let frame = NSBezierPath(roundedRect: bar.insetBy(dx: -bezel, dy: -bezel), xRadius: 18, yRadius: 18)
    hex("#0d1220").setFill()
    frame.fill()
    frame.lineWidth = 2
    hex("#2a3654").setStroke()
    frame.stroke()
    hex("#000000").setFill()
    NSBezierPath(roundedRect: bar, xRadius: 8, yRadius: 8).fill()
    if row.lit {
        let stripWidth = CGFloat(controlStrip.width) * barWidth / CGFloat(captureCG.width)
        cg.interpolationQuality = .high
        cg.draw(controlStrip, in: CGRect(x: bar.maxX - stripWidth, y: bar.minY, width: stripWidth, height: bar.height))
    }

    // "5 s" badge, centred vertically in the last bar.
    if row.title.hasSuffix("Peek") {
        // A timer badge: SF Symbols' "timer" glyph plus "5 s", centred in the bar's height.
        let label = Line("5 s", NSFont.systemFont(ofSize: 19, weight: .bold), .white)
        let iconSize: CGFloat = 20, padL: CGFloat = 9, gap: CGFloat = 6, padR: CGFloat = 12
        let badge = NSRect(x: bar.minX + 10, y: bar.midY - 14,
                           width: padL + iconSize + gap + label.ink.width + padR, height: 28)
        hex("#3a8bff").setFill()
        NSBezierPath(roundedRect: badge, xRadius: 14, yRadius: 14).fill()
        if let timer = timerSymbol(size: iconSize) {
            timer.draw(in: NSRect(x: badge.minX + padL, y: badge.midY - timer.size.height / 2,
                                  width: timer.size.width, height: timer.size.height))
        }
        let textCentre = CGPoint(x: badge.minX + padL + iconSize + gap + label.ink.width / 2, y: badge.midY)
        label.drawInkCentered(at: textCentre)
    }
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("Wrote \(args[2]): margins \(Int(margin)) px, bar \(Int(barWidth))×\(Int(barHeight)) px, control strip from x=\(stripStart)")
