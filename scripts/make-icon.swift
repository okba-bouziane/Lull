// Draws the Lull app icon and writes an .iconset folder. Usage: swift make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let s = size / 1024
        let box = rect.insetBy(dx: 100 * s, dy: 100 * s)
        let tile = NSBezierPath(roundedRect: box, xRadius: 185 * s, yRadius: 185 * s)
        NSGradient(colors: [NSColor(red: 0.36, green: 0.36, blue: 0.86, alpha: 1),
                            NSColor(red: 0.20, green: 0.19, blue: 0.55, alpha: 1)])!.draw(in: tile, angle: -90)

        let center = NSPoint(x: 512 * s, y: 430 * s)
        let radius = 250 * s

        // Track
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 200, endAngle: -20, clockwise: true)
        track.lineWidth = 64 * s; track.lineCapStyle = .round
        NSColor(white: 1, alpha: 0.22).setStroke(); track.stroke()

        // Calm part of the gauge (low load)
        let calm = NSBezierPath()
        calm.appendArc(withCenter: center, radius: radius, startAngle: 200, endAngle: 125, clockwise: true)
        calm.lineWidth = 64 * s; calm.lineCapStyle = .round
        NSColor(red: 0.55, green: 0.92, blue: 0.75, alpha: 1).setStroke(); calm.stroke()

        // Needle resting low
        let angle = 140 * CGFloat.pi / 180
        let tip = NSPoint(x: center.x + cos(angle) * (radius - 70 * s), y: center.y + sin(angle) * (radius - 70 * s))
        let needle = NSBezierPath()
        needle.move(to: center); needle.line(to: tip)
        needle.lineWidth = 40 * s; needle.lineCapStyle = .round
        NSColor.white.setStroke(); needle.stroke()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 52 * s, y: center.y - 52 * s, width: 104 * s, height: 104 * s)).fill()
        return true
    }
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(px).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
print("iconset written")
