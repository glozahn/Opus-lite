// Genera Resources/AppIcon.icns. Uso: swift Tools/make_icon.swift
import AppKit

let size: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) in CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }

// Cuerpo tipo squircle (rejilla de iconos macOS: 824 px con margen de 100).
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(18, 140, 126, 1)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
let bg = CGGradient(colorsSpace: nil, colors: [rgb(52, 222, 124, 1), rgb(7, 94, 84, 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 200, y: 924), end: CGPoint(x: 824, y: 100), options: [])
// Brillo superior.
let gloss = CGGradient(colorsSpace: nil, colors: [rgb(255, 255, 255, 0.18), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
ctx.restoreGState()

// Globo de chat con cola abajo a la izquierda.
let bubble = CGRect(x: 215, y: 330, width: 594, height: 420)
let bubblePath = CGMutablePath()
bubblePath.addRoundedRect(in: bubble, cornerWidth: 130, cornerHeight: 130)
bubblePath.move(to: CGPoint(x: 300, y: 360))
bubblePath.addCurve(to: CGPoint(x: 230, y: 250), control1: CGPoint(x: 300, y: 300), control2: CGPoint(x: 270, y: 265))
bubblePath.addCurve(to: CGPoint(x: 400, y: 340), control1: CGPoint(x: 310, y: 250), control2: CGPoint(x: 370, y: 290))
bubblePath.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 40, 30, 0.35))
ctx.addPath(bubblePath); ctx.setFillColor(rgb(255, 255, 255, 1)); ctx.fillPath()
ctx.restoreGState()

// Ondas (izquierda) que se convierten en líneas de texto (derecha).
let midY = bubble.midY
let green = rgb(18, 170, 110, 1)
let bars: [CGFloat] = [70, 150, 220, 130, 190, 90]
for (i, h) in bars.enumerated() {
    let x = 285 + CGFloat(i) * 42
    let r = CGRect(x: x, y: midY - h / 2, width: 24, height: h)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil))
    ctx.setFillColor(green); ctx.fillPath()
}
// Flecha sutil.
ctx.setFillColor(rgb(18, 170, 110, 0.45))
ctx.move(to: CGPoint(x: 548, y: midY + 26)); ctx.addLine(to: CGPoint(x: 574, y: midY)); ctx.addLine(to: CGPoint(x: 548, y: midY - 26)); ctx.fillPath()
let lines: [(CGFloat, CGFloat)] = [(midY + 70, 150), (midY, 150), (midY - 70, 100)]
for (y, w) in lines {
    let r = CGRect(x: 600, y: y - 14, width: w, height: 28)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(rgb(60, 72, 80, 0.85)); ctx.fillPath()
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
