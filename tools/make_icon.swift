// Renders the 1024×1024 app icon.
// Usage: swift tools/make_icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let size = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

// App Store Connect rejects icons with an alpha channel, so draw into an opaque RGB context.
guard let cg = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("could not create bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)

func rgb(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// Background
let full = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(starting: rgb(0x5A6BEA), ending: rgb(0x2B3592))!.draw(in: full, angle: -60)

func bubble(_ rect: NSRect, tailLeft: Bool, fill: NSColor) {
    let path = NSBezierPath(roundedRect: rect, xRadius: 120, yRadius: 120)
    let tail = NSBezierPath()
    if tailLeft {
        tail.move(to: NSPoint(x: rect.minX + 90, y: rect.minY + 40))
        tail.line(to: NSPoint(x: rect.minX + 40, y: rect.minY - 70))
        tail.line(to: NSPoint(x: rect.minX + 200, y: rect.minY + 10))
    } else {
        tail.move(to: NSPoint(x: rect.maxX - 90, y: rect.minY + 40))
        tail.line(to: NSPoint(x: rect.maxX - 40, y: rect.minY - 70))
        tail.line(to: NSPoint(x: rect.maxX - 200, y: rect.minY + 10))
    }
    tail.close()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 30
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    fill.setFill()
    path.fill()
    tail.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func label(_ text: String, in rect: NSRect, color: NSColor, font: NSFont) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
    let str = NSAttributedString(string: text, attributes: attrs)
    let h = str.size().height
    str.draw(in: NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h))
}

let left = NSRect(x: 150, y: 430, width: 470, height: 400)
let right = NSRect(x: 404, y: 194, width: 470, height: 400)
bubble(left, tailLeft: true, fill: .white)
bubble(right, tailLeft: false, fill: rgb(0xFF7A59))

label("Ä", in: left, color: rgb(0x3B47B8), font: .systemFont(ofSize: 270, weight: .bold))
let cjk = NSFont(name: "PingFangSC-Semibold", size: 250) ?? .systemFont(ofSize: 250, weight: .bold)
label("字", in: right, color: .white, font: cjk)

NSGraphicsContext.restoreGraphicsState()

guard let image = cg.makeImage() else { fatalError("could not make image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
