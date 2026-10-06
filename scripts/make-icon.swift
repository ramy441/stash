import AppKit

// Draws the app icon: a stack of cards with the top one lifted back out, which is the
// whole product in one shape — layers of past clips, one coming back to your hands.
let outDir = CommandLine.arguments[1]
let side: CGFloat = 1024

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let ctx = NSGraphicsContext.current!.cgContext

// macOS app-icon squircle: 1024 canvas, art inset ~100, corner radius ~185
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185
let platePath = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

// deep indigo → violet, the "kept safe" end of the palette rather than a warning colour
ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [CGColor(red: 0.16, green: 0.17, blue: 0.42, alpha: 1),
                             CGColor(red: 0.35, green: 0.24, blue: 0.68, alpha: 1)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: plate.minX, y: plate.maxY),
                       end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
// soft light from the top-left corner, no hard edge
let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
                                CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: plate.minX + 180, y: plate.maxY - 120),
                       startRadius: 0, endCenter: CGPoint(x: plate.minX + 180, y: plate.maxY - 120),
                       endRadius: 620, options: [])
ctx.restoreGState()

/// The card stack. Back cards are dimmer and inset so depth survives a 16 px render.
func card(_ rect: CGRect, alpha: CGFloat) {
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34,
                  color: CGColor(red: 0.05, green: 0.03, blue: 0.15, alpha: 0.45))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 44, cornerHeight: 44, transform: nil))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
}

// centred and stepped so each older clip shows a thin band above the current one
card(CGRect(x: 327, y: 450, width: 370, height: 255), alpha: 0.28)
card(CGRect(x: 302, y: 400, width: 420, height: 255), alpha: 0.52)
let front = CGRect(x: 277, y: 300, width: 470, height: 300)
card(front, alpha: 1.0)

// text lines on the front card — reads as "this is a saved clip", not a blank sheet
ctx.setFillColor(CGColor(red: 0.30, green: 0.28, blue: 0.55, alpha: 1))
for (index, width) in [CGFloat(290), 340, 210].enumerated() {
    let y = front.maxY - 92 - CGFloat(index) * 72
    ctx.addPath(CGPath(roundedRect: CGRect(x: front.minX + 60, y: y, width: width, height: 34),
                       cornerWidth: 17, cornerHeight: 17, transform: nil))
}
ctx.fillPath()

NSGraphicsContext.restoreGraphicsState()

let png = bitmap.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outDir + "/icon_1024.png"))
print("wrote icon_1024.png")
