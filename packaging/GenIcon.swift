// Renders the Beachman Darkroom app icon at 1024×1024.
// Usage: swift GenIcon.swift /path/to/icon_1024.png
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024

let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()

// macOS icon grid: rounded rect with margins
let margin: CGFloat = 100
let rect = NSRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let rr = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

// Navy vertical gradient
let navyTop = NSColor(srgbRed: 0.16, green: 0.21, blue: 0.35, alpha: 1)
let navyBot = NSColor(srgbRed: 0.07, green: 0.10, blue: 0.19, alpha: 1)
NSGradient(starting: navyTop, ending: navyBot)!.draw(in: rr, angle: -90)

rr.setClip()

// Sun — Beachman orange circle, upper half
let sun = NSBezierPath(ovalIn: NSRect(x: S/2 - 190, y: 400, width: 380, height: 380))
NSColor(srgbRed: 0.91, green: 0.45, blue: 0.17, alpha: 1).setFill()
sun.fill()

// Soft sun glow
let glow = NSBezierPath(ovalIn: NSRect(x: S/2 - 250, y: 340, width: 500, height: 500))
NSColor(srgbRed: 0.91, green: 0.45, blue: 0.17, alpha: 0.18).setFill()
glow.fill()

// Cream "water" lines — mid-century waves under the sun
let cream = NSColor(srgbRed: 0.97, green: 0.94, blue: 0.87, alpha: 1)
let widths: [CGFloat] = [560, 440, 320, 200]
for (i, w) in widths.enumerated() {
    let y = 350 - CGFloat(i) * 62
    let line = NSBezierPath(roundedRect: NSRect(x: S/2 - w/2, y: y, width: w, height: 26),
                            xRadius: 13, yRadius: 13)
    cream.withAlphaComponent(1.0 - CGFloat(i) * 0.18).setFill()
    line.fill()
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("render failed")
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
