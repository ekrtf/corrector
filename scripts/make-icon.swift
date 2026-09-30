// Draws the Corrector app icon and writes Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift                      # regenerate Resources/AppIcon.icns
//   swift scripts/make-icon.swift --preview DIR        # write PNG previews to DIR instead
//   --variant b (default): graphite "é" with a blue check on white
//   --variant a: white "é" on blue;  --variant c: graphite "é" on a white sheet over blue
//
// One idea: a lowercase "é" whose acute accent is a check mark. The accent is the correction.
// Vector-only (no fonts, no SF Symbols), on the macOS icon grid: a 1024 px canvas holding an 824 px
// continuous-corner body with a soft drop shadow. Every size is rendered from the vectors, and the
// output is byte-reproducible.

import CoreGraphics
import Foundation
import ImageIO

let canvas: CGFloat = 1024
let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185.4

typealias Stops = [(CGFloat, CGColor)]

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: Stops) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: stops.map(\.1) as CFArray,
        locations: stops.map(\.0)
    )!
}

extension CGVector {
    var normalized: CGVector {
        let length = (dx * dx + dy * dy).squareRoot()
        return CGVector(dx: dx / length, dy: dy / length)
    }
}

// Rounded rectangle with Figma-style corner smoothing; 0.6 approximates Apple's continuous corners.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat, smoothing: CGFloat = 0.6) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2 / (1 + smoothing))
    let p = (1 + smoothing) * r
    let arcMeasure = CGFloat.pi / 2 * (1 - smoothing)
    let arcLength = sin(arcMeasure / 2) * r * 2.squareRoot()
    let alpha = (CGFloat.pi / 2 - arcMeasure) / 2
    let beta = CGFloat.pi / 4 * smoothing
    let c = r * tan(alpha / 2) * cos(beta)
    let d = c * tan(beta)
    let b = (p - arcLength - c - d) / 3
    let a = 2 * b

    // One corner in local coordinates: x = inset from the vertical edge, y = inset from the horizontal edge.
    let p1 = CGPoint(x: p - a - b - c, y: d)
    let p2 = CGPoint(x: d, y: d + arcLength)
    let t1 = CGVector(dx: -c, dy: d).normalized
    let t2 = CGVector(dx: -d, dy: c).normalized
    let k = 4 / 3 * tan(arcMeasure / 4) * r
    let corner = [
        CGPoint(x: p, y: 0),
        CGPoint(x: p - a, y: 0), CGPoint(x: p - a - b, y: 0), p1,
        CGPoint(x: p1.x + t1.dx * k, y: p1.y + t1.dy * k), CGPoint(x: p2.x - t2.dx * k, y: p2.y - t2.dy * k), p2,
        CGPoint(x: 0, y: d + arcLength + c), CGPoint(x: 0, y: d + arcLength + b + c), CGPoint(x: 0, y: p),
    ]

    let path = CGMutablePath()
    func addCorner(reversed: Bool, _ map: (CGPoint) -> CGPoint) {
        let points = (reversed ? corner.reversed() : corner).map(map)
        if path.isEmpty { path.move(to: points[0]) } else { path.addLine(to: points[0]) }
        for i in stride(from: 1, to: points.count, by: 3) {
            path.addCurve(to: points[i + 2], control1: points[i], control2: points[i + 1])
        }
    }
    addCorner(reversed: false) { CGPoint(x: rect.maxX - $0.x, y: rect.minY + $0.y) }
    addCorner(reversed: true) { CGPoint(x: rect.maxX - $0.x, y: rect.maxY - $0.y) }
    addCorner(reversed: false) { CGPoint(x: rect.minX + $0.x, y: rect.maxY - $0.y) }
    addCorner(reversed: true) { CGPoint(x: rect.minX + $0.x, y: rect.minY + $0.y) }
    path.closeSubpath()
    return path
}

// The glyph, measured in units of the letter's half-height and centred on `center` (y-down).
struct Glyph {
    let letter: CGPath
    let check: CGPath

    init(center: CGPoint, size ry: CGFloat) {
        // Round letters are drawn a touch taller than wide, and horizontals thinner than verticals,
        // so the stroke reads as one even weight.
        let rx = ry * 0.95
        let stem = ry * 0.38
        let hair = stem * 0.86
        let bar = stem * 0.80
        let checkWidth = stem * 0.92
        let gap = ry * 0.16
        let longArm = CGVector(dx: ry * 0.50, dy: -ry * 0.66)
        let shortArm = CGVector(dx: -ry * 0.31, dy: -ry * 0.27)

        // Centre the letter-plus-accent group on `center`.
        let groupHeight = 2 * ry + gap + checkWidth - longArm.dy
        let c = CGPoint(x: center.x, y: center.y + groupHeight / 2 - ry)

        let outer = CGPath(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry), transform: nil)
        let inner = CGPath(
            ellipseIn: CGRect(x: c.x - rx + stem, y: c.y - ry + hair, width: 2 * (rx - stem), height: 2 * (ry - hair)),
            transform: nil
        )
        let barCenter = c.y - ry * 0.05
        let barBottom = barCenter + bar / 2

        // The aperture: everything right of the counter between the crossbar and an angled terminal cut.
        let terminal = CGFloat.pi / 180 * 34
        let cut = CGFloat.pi / 180 * 52
        let cutDirection = CGVector(dx: cos(cut), dy: sin(cut))
        let onStroke = CGPoint(x: c.x + (rx - stem / 2) * cos(terminal), y: c.y + (ry - hair / 2) * sin(terminal))
        let aperture = CGMutablePath()
        aperture.addLines(between: [
            CGPoint(x: c.x, y: barBottom),
            CGPoint(x: c.x + 3 * rx, y: barBottom),
            CGPoint(x: onStroke.x + cutDirection.dx * 3 * rx, y: onStroke.y + cutDirection.dy * 3 * rx),
            CGPoint(x: onStroke.x - cutDirection.dx * stem, y: onStroke.y - cutDirection.dy * stem),
        ])
        aperture.closeSubpath()
        let crossbar = CGPath(
            rect: CGRect(x: c.x - rx + stem / 2, y: barCenter - bar / 2, width: 2 * rx - stem, height: bar),
            transform: nil
        )
        letter = outer.subtracting(inner).subtracting(aperture).union(crossbar)

        // The check's long stroke has the slant of an acute accent and sits right of centre, like one.
        let vertex = CGPoint(x: c.x + rx * 0.06, y: c.y - ry - gap - checkWidth / 2)
        let mark = CGMutablePath()
        mark.addLines(between: [
            CGPoint(x: vertex.x + shortArm.dx, y: vertex.y + shortArm.dy),
            vertex,
            CGPoint(x: vertex.x + longArm.dx, y: vertex.y + longArm.dy),
        ])
        check = mark.copy(strokingWithWidth: checkWidth, lineCap: .round, lineJoin: .round, miterLimit: 10).normalized()
    }
}

struct Style {
    var background: Stops
    var sheen: CGFloat
    var hairline: CGColor?
    var sheet: Bool
    var letter: Stops
    var check: Stops
    var glyphShadow: CGColor
    var glyphSize: CGFloat

    static let variants: [String: Style] = [
        // White glyph on system blue.
        "a": Style(
            background: [(0, rgb(0x52ADFF)), (1, rgb(0x0A5FE0))], sheen: 0.18, hairline: nil, sheet: false,
            letter: [(0, rgb(0xFFFFFF)), (1, rgb(0xE6EFFD))], check: [(0, rgb(0xFFFFFF)), (1, rgb(0xE6EFFD))],
            glyphShadow: rgb(0x06327A, 0.24), glyphSize: 170
        ),
        // Graphite glyph and a blue check on white.
        "b": Style(
            background: [(0, rgb(0xFFFFFF)), (1, rgb(0xE8EAEF))], sheen: 0, hairline: rgb(0x000000, 0.06), sheet: false,
            letter: [(0, rgb(0x41444D)), (1, rgb(0x1E2026))], check: [(0, rgb(0x3FA2FF)), (1, rgb(0x0A64EC))],
            glyphShadow: rgb(0x000000, 0.14), glyphSize: 170
        ),
        // A single sheet on system blue carrying a graphite glyph and a green check.
        "c": Style(
            background: [(0, rgb(0x52ADFF)), (1, rgb(0x0A5FE0))], sheen: 0.18, hairline: nil, sheet: true,
            letter: [(0, rgb(0x41444D)), (1, rgb(0x1E2026))], check: [(0, rgb(0x3ED46A)), (1, rgb(0x1E9E48))],
            glyphShadow: rgb(0x000000, 0.14), glyphSize: 128
        ),
    ]
}

// Drawing happens in a 1024-unit, y-down space; `scale` maps it to output pixels.
struct IconRenderer {
    let pixels: Int
    let style: Style
    var scale: CGFloat { CGFloat(pixels) / canvas }

    // Sheet edges sit on the 16 px and 32 px pixel grids so the small sizes stay sharp.
    let sheetRect = CGRect(x: 256, y: 192, width: 512, height: 640)

    func render() -> CGImage {
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: scale, y: -scale)
        drawBody(context)
        let center: CGPoint
        if style.sheet {
            drawSheet(context)
            center = CGPoint(x: sheetRect.midX, y: sheetRect.midY - 4)
        } else {
            center = CGPoint(x: 512, y: 498)
        }
        drawGlyph(context, Glyph(center: center, size: style.glyphSize))
        return context.makeImage()!
    }

    // Shadow offsets and blur are in device pixels and y-up, independent of the CTM.
    func setShadow(_ context: CGContext, y: CGFloat, blur: CGFloat, color: CGColor) {
        context.setShadow(offset: CGSize(width: 0, height: -y * scale), blur: blur * scale, color: color)
    }

    func fill(_ context: CGContext, _ path: CGPath, in bounds: CGRect, _ stops: Stops) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient(stops), start: CGPoint(x: 0, y: bounds.minY), end: CGPoint(x: 0, y: bounds.maxY), options: []
        )
        context.restoreGState()
    }

    // Shades the inside of `path` along its lower edge, so the shape reads as gently rounded.
    func innerShadow(_ context: CGContext, _ path: CGPath, y: CGFloat, blur: CGFloat, color: CGColor) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        setShadow(context, y: y, blur: blur, color: color)
        context.addRect(CGRect(x: -canvas, y: -canvas, width: canvas * 3, height: canvas * 3))
        context.addPath(path)
        context.setFillColor(rgb(0x000000))
        context.fillPath(using: .evenOdd)
        context.restoreGState()
    }

    func drawBody(_ context: CGContext) {
        let body = continuousRoundedRect(bodyRect, radius: bodyRadius)

        context.saveGState()
        setShadow(context, y: 12, blur: 28, color: rgb(0x000000, 0.30))
        context.addPath(body)
        context.setFillColor(style.background[0].1)
        context.fillPath()
        context.restoreGState()

        fill(context, body, in: bodyRect, style.background)
        if style.sheen > 0 {
            fill(context, body, in: CGRect(x: 0, y: bodyRect.minY, width: canvas, height: bodyRect.height * 0.55), [
                (0, rgb(0xFFFFFF, style.sheen)), (1, rgb(0xFFFFFF, 0)),
            ])
        }
        if let hairline = style.hairline {
            context.saveGState()
            context.addPath(body)
            context.clip()
            context.addPath(body)
            context.setLineWidth(4)
            context.setStrokeColor(hairline)
            context.strokePath()
            context.restoreGState()
        }
    }

    func drawSheet(_ context: CGContext) {
        let sheet = continuousRoundedRect(sheetRect, radius: 36)
        context.saveGState()
        setShadow(context, y: 14, blur: 36, color: rgb(0x0A2A6E, 0.40))
        context.addPath(sheet)
        context.setFillColor(rgb(0xFFFFFF))
        context.fillPath()
        context.restoreGState()
        fill(context, sheet, in: sheetRect, [(0, rgb(0xFFFFFF)), (1, rgb(0xEEF1F6))])
    }

    func drawGlyph(_ context: CGContext, _ glyph: Glyph) {
        let bounds = glyph.letter.boundingBox.union(glyph.check.boundingBox)
        let both = glyph.letter.union(glyph.check)

        context.saveGState()
        setShadow(context, y: 6, blur: 16, color: style.glyphShadow)
        context.addPath(both)
        context.setFillColor(style.letter[0].1)
        context.fillPath()
        context.restoreGState()

        fill(context, glyph.letter, in: bounds, style.letter)
        fill(context, glyph.check, in: glyph.check.boundingBox, style.check)
        innerShadow(context, both, y: -4, blur: 10, color: rgb(0x000000, 0.10))
    }
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    guard index + 1 < arguments.count else { fail("usage: make-icon.swift [--variant a|b|c] [--preview DIR]") }
    return arguments[index + 1]
}

let variant = option("--variant") ?? "b"
guard let style = Style.variants[variant] else { fail("unknown variant \(variant); use a, b or c") }

if let preview = option("--preview") {
    let directory = URL(fileURLWithPath: preview)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    for pixels in [1024, 256, 128, 64, 32, 16] {
        let image = IconRenderer(pixels: pixels, style: style).render()
        try writePNG(image, to: directory.appendingPathComponent("icon-\(pixels).png"))
    }
    print("Wrote variant \(variant) previews to \(directory.path)")
    exit(0)
}

let work = fileManager.temporaryDirectory.appendingPathComponent("corrector-icon-\(UUID().uuidString)")
let iconset = work.appendingPathComponent("AppIcon.iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let image = IconRenderer(pixels: points * factor, style: style).render()
        try writePNG(image, to: iconset.appendingPathComponent(name))
    }
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? fileManager.removeItem(at: work)
guard iconutil.terminationStatus == 0 else { fail("iconutil failed with status \(iconutil.terminationStatus)") }
print("Wrote variant \(variant) to \(output.path)")
