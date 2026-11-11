// Renders the Riptide logo with Core Graphics.
// Usage: swift make_icon.swift <out.png> [size=1024] [--glyph]
//   default: full macOS app icon (squircle, ocean gradient, arrow + waves)
//   --glyph: the white mark only, on a transparent background
import AppKit
import CoreGraphics

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "icon.png"
let size = args.count > 2 ? (Int(args[2]) ?? 1024) : 1024
let glyphOnly = args.contains("--glyph")

let S = CGFloat(size)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// 1024-unit canvas, origin top-left.
ctx.scaleBy(x: S / 1024, y: S / 1024)
ctx.translateBy(x: 0, y: 1024)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Superellipse ("squircle") like the macOS icon shape.
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    for i in 0...360 {
        let t = CGFloat(i) * .pi / 180
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

/// A wave band: smooth top edge through the given crest/trough points, filled down to `bottom`.
func waveBand(_ pts: [CGPoint], bottom: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: pts[0])
    for i in 1..<pts.count {
        let a = pts[i - 1], b = pts[i], mx = (a.x + b.x) / 2
        p.addCurve(to: b, control1: CGPoint(x: mx, y: a.y), control2: CGPoint(x: mx, y: b.y))
    }
    p.addLine(to: CGPoint(x: pts.last!.x, y: bottom))
    p.addLine(to: CGPoint(x: pts[0].x, y: bottom))
    p.closeSubpath()
    return p
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = squircle(body)

if !glyphOnly {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 24, color: rgb(0x000000, 0.30))
    ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x0B2E6F)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [rgb(0x0B1F5C), rgb(0x1351B4), rgb(0x1FB8CD)] as CFArray,
                       locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 160), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 160), endRadius: 560, options: [])
    ctx.restoreGState()
}

// --- Mark: a down arrow dropping into two waves ---
ctx.saveGState()
if !glyphOnly { ctx.addPath(bodyPath); ctx.clip() }

// Back wave (translucent)
let back = waveBand([CGPoint(x: 60, y: 640), CGPoint(x: 260, y: 590), CGPoint(x: 512, y: 650),
                     CGPoint(x: 760, y: 590), CGPoint(x: 964, y: 640)], bottom: 964)
ctx.addPath(back); ctx.setFillColor(rgb(0xFFFFFF, glyphOnly ? 0.45 : 0.34)); ctx.fillPath()

// Front wave
let front = waveBand([CGPoint(x: 60, y: 775), CGPoint(x: 300, y: 725), CGPoint(x: 512, y: 785),
                      CGPoint(x: 724, y: 725), CGPoint(x: 964, y: 775)], bottom: 964)
ctx.addPath(front); ctx.setFillColor(glyphOnly ? rgb(0xFFFFFF, 0.85) : rgb(0xDDF7FF, 0.95)); ctx.fillPath()
ctx.restoreGState()

// Arrow (drawn last so it sits on top, tip dipping into the back wave)
ctx.saveGState()
if !glyphOnly { ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 20, color: rgb(0x041A4A, 0.40)) }
ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(78)
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 512, y: 230)); arrow.addLine(to: CGPoint(x: 512, y: 560))
arrow.move(to: CGPoint(x: 378, y: 430)); arrow.addLine(to: CGPoint(x: 512, y: 565)); arrow.addLine(to: CGPoint(x: 646, y: 430))
ctx.addPath(arrow); ctx.strokePath()
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(size)px)")
