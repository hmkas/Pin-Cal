import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Flip to top-left origin for easier reasoning
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)

let page = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185
let pagePath = CGPath(roundedRect: page, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: NSColor.black.withAlphaComponent(0.28).cgColor)
ctx.addPath(pagePath); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
ctx.restoreGState()

// Page gradient + header
ctx.saveGState()
ctx.addPath(pagePath); ctx.clip()
let cs = CGColorSpaceCreateDeviceRGB()
let white = CGGradient(colorsSpace: cs, colors: [NSColor(white: 1, alpha: 1).cgColor, NSColor(white: 0.93, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(white, start: CGPoint(x: 0, y: page.minY), end: CGPoint(x: 0, y: page.maxY), options: [])
let header = CGRect(x: page.minX, y: page.minY, width: page.width, height: 230)
let red = CGGradient(colorsSpace: cs, colors: [NSColor(red: 1.0, green: 0.36, blue: 0.32, alpha: 1).cgColor, NSColor(red: 0.89, green: 0.16, blue: 0.15, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
ctx.saveGState(); ctx.clip(to: header)
ctx.drawLinearGradient(red, start: CGPoint(x: 0, y: header.minY), end: CGPoint(x: 0, y: header.maxY), options: [])
ctx.restoreGState()
ctx.restoreGState()

// Text helper (draws in flipped context)
func draw(_ s: String, font: NSFont, color: NSColor, centerX: CGFloat, centerY: CGFloat, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let str = NSAttributedString(string: s, attributes: attrs)
    let line = CTLineCreateWithAttributedString(str)
    let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: centerX - b.width / 2 - b.minX, y: centerY + b.height / 2 + b.minY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}
draw("PIN-CAL", font: .systemFont(ofSize: 112, weight: .heavy), color: .white, centerX: 512, centerY: 215, kern: 6)
draw("17", font: .systemFont(ofSize: 420, weight: .semibold), color: NSColor(white: 0.13, alpha: 1), centerX: 430, centerY: 610, kern: -12)

// Pushpin: point in the page, head up-right
let tip = CGPoint(x: 655, y: 735)
let angle: CGFloat = 0.62 // radians, leaning to the upper right
let needleLen: CGFloat = 120
let dir = CGPoint(x: sin(angle), y: -cos(angle)) // same axis as the rotated pin body
let neck = CGPoint(x: tip.x + dir.x * needleLen, y: tip.y + dir.y * needleLen)

// Hole + shadow on the page
ctx.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 22, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
ctx.fillEllipse(in: CGRect(x: tip.x - 6, y: tip.y - 14, width: 190, height: 40))
ctx.restoreGState()
ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.fillEllipse(in: CGRect(x: tip.x - 9, y: tip.y - 5, width: 18, height: 10))

// Needle
ctx.saveGState()
ctx.setLineCap(.round)
ctx.setLineWidth(16)
ctx.setStrokeColor(NSColor(white: 0.55, alpha: 1).cgColor)
ctx.move(to: tip); ctx.addLine(to: neck); ctx.strokePath()
ctx.setLineWidth(5)
ctx.setStrokeColor(NSColor(white: 0.88, alpha: 1).cgColor)
ctx.move(to: CGPoint(x: tip.x - 3, y: tip.y)); ctx.addLine(to: CGPoint(x: neck.x - 3, y: neck.y)); ctx.strokePath()
ctx.restoreGState()

// Pin body (drawn in rotated frame along the needle axis)
ctx.saveGState()
ctx.translateBy(x: neck.x, y: neck.y)
ctx.rotate(by: angle)
ctx.setShadow(offset: CGSize(width: 6, height: 12), blur: 18, color: NSColor.black.withAlphaComponent(0.35).cgColor)
let pinRed = NSColor(red: 0.92, green: 0.12, blue: 0.14, alpha: 1)
let body = CGMutablePath()
// collar (wide disc), waist, top cap — y negative = away from needle
body.addEllipse(in: CGRect(x: -95, y: -40, width: 190, height: 56))           // base disc
body.move(to: CGPoint(x: -48, y: -20)); body.addLine(to: CGPoint(x: -40, y: -150))
body.addLine(to: CGPoint(x: 40, y: -150)); body.addLine(to: CGPoint(x: 48, y: -20)); body.closeSubpath() // waist
body.addEllipse(in: CGRect(x: -80, y: -195, width: 160, height: 70))          // top cap
ctx.addPath(body); ctx.setFillColor(pinRed.cgColor); ctx.fillPath()
ctx.restoreGState()

// Highlights (no shadow)
ctx.saveGState()
ctx.translateBy(x: neck.x, y: neck.y)
ctx.rotate(by: angle)
let dark = NSColor(red: 0.62, green: 0.05, blue: 0.08, alpha: 1)
ctx.setFillColor(dark.cgColor)
ctx.fillEllipse(in: CGRect(x: -95, y: -24, width: 190, height: 40))           // underside of base
ctx.setFillColor(pinRed.cgColor)
ctx.fillEllipse(in: CGRect(x: -95, y: -40, width: 190, height: 48))
ctx.setFillColor(NSColor(red: 1, green: 0.42, blue: 0.40, alpha: 1).cgColor)
ctx.fillEllipse(in: CGRect(x: -80, y: -195, width: 160, height: 62))          // cap top lighter
ctx.setFillColor(NSColor.white.withAlphaComponent(0.55).cgColor)
ctx.fillEllipse(in: CGRect(x: -50, y: -186, width: 55, height: 20))           // gloss
ctx.fillEllipse(in: CGRect(x: -30, y: -140, width: 14, height: 100))          // waist gloss
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
