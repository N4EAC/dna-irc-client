import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let outer = NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 210, yRadius: 210)
NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.12, alpha: 1).setFill()
outer.fill()
let face = NSBezierPath(roundedRect: NSRect(x: 85, y: 85, width: 854, height: 854), xRadius: 160, yRadius: 160)
NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.065, alpha: 1).setFill()
face.fill()
face.lineWidth = 14
NSColor(calibratedRed: 0.33, green: 0.34, blue: 0.28, alpha: 1).setStroke()
face.stroke()
let amber = NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.33, alpha: 1)
let font = NSFont.monospacedSystemFont(ofSize: 270, weight: .bold)
let text = "DNA" as NSString
let shadow = NSShadow()
shadow.shadowColor = amber.withAlphaComponent(0.75)
shadow.shadowBlurRadius = 28
let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: amber, .shadow: shadow]
let width = text.size(withAttributes: attributes).width
text.draw(at: NSPoint(x: (CGFloat(size) - width) / 2, y: 370), withAttributes: attributes)
let accent = NSBezierPath(roundedRect: NSRect(x: 208, y: 252, width: 608, height: 17), xRadius: 8, yRadius: 8)
amber.withAlphaComponent(0.8).setFill()
accent.fill()
for x in [208.0, 250.0, 292.0] {
    let dot = NSBezierPath(ovalIn: NSRect(x: x, y: 776, width: 17, height: 17))
    amber.withAlphaComponent(0.85).setFill()
    dot.fill()
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: "Assets/DNA-1024.png"))
