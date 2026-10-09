import AppKit
// swift make-icon.swift clawd.png AppIcon.iconset
let src = NSImage(contentsOfFile: CommandLine.arguments[1])!
let dir = CommandLine.arguments[2]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
func render(_ px: Int, _ name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), r = NSRect(x: s*0.05, y: s*0.05, width: s*0.9, height: s*0.9)
    NSColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1).setFill()
    NSBezierPath(roundedRect: r, xRadius: s*0.2, yRadius: s*0.2).fill()
    NSGraphicsContext.current!.imageInterpolation = .none   // чіткі пікселі
    let w = s*0.6
    src.draw(in: NSRect(x: (s-w)/2, y: (s-w)/2, width: w, height: w))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
for b in [16, 32, 128, 256, 512] { render(b, "icon_\(b)x\(b)"); render(b*2, "icon_\(b)x\(b)@2x") }
