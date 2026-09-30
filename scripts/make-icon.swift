// Draws the Corrector app icon and writes Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift                 # regenerate Resources/AppIcon.icns
//   swift scripts/make-icon.swift --preview DIR   # also write PNG previews to DIR
//
// The artwork is vector-only (no fonts, no SF Symbols) and follows the macOS icon grid: a 1024 px canvas
// holding an 824 px continuous-corner body with a soft drop shadow. Each iconset size is rendered from the
// vectors, so small sizes stay crisp; 16 and 32 px drop the back sheet, whose rotated edges blur there.
//
// Concept: a sheet of text whose big "é" has a green check mark for its acute accent. The accent is the
// correction.

import CoreGraphics
import Foundation
import ImageIO

let canvas: CGFloat = 1024
let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185.4

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
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

func polyline(_ points: CGPoint...) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    return path
}

// Drawing happens in a 1024-unit, y-down space; `scale` maps it to output pixels.
struct IconRenderer {
    let pixels: Int
    var scale: CGFloat { CGFloat(pixels) / canvas }
    var showsBackSheet: Bool { pixels >= 64 }

    // Paper edges sit on the 16 px and 32 px pixel grids so the small sizes stay sharp.
    let paperRect = CGRect(x: 256, y: 176, width: 512, height: 672)
    let paperRadius: CGFloat = 34
    let letterCenter = CGPoint(x: 512, y: 526)
    let letterRadius: CGFloat = 100

    func render() -> CGImage {
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: scale, y: -scale)
        drawBody(context)
        if showsBackSheet { drawBackSheet(context) }
        drawPaper(context)
        drawLines(context)
        drawLetter(context)
        drawCheckAccent(context)
        return context.makeImage()!
    }

    // Shadow offsets and blur are in device pixels and y-up, independent of the CTM.
    func setShadow(_ context: CGContext, y: CGFloat, blur: CGFloat, color: CGColor) {
        context.setShadow(offset: CGSize(width: 0, height: -y * scale), blur: blur * scale, color: color)
    }

    func fill(_ context: CGContext, _ path: CGPath, top: CGFloat, bottom: CGFloat, _ stops: [(CGFloat, CGColor)]) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient(stops), start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: []
        )
        context.restoreGState()
    }

    func drawBody(_ context: CGContext) {
        let body = continuousRoundedRect(bodyRect, radius: bodyRadius)

        context.saveGState()
        setShadow(context, y: 12, blur: 28, color: rgb(0x000000, 0.32))
        context.addPath(body)
        context.setFillColor(rgb(0x3F5BEF))
        context.fillPath()
        context.restoreGState()

        fill(context, body, top: bodyRect.minY, bottom: bodyRect.maxY, [
            (0, rgb(0x5B8CFF)), (0.55, rgb(0x3F5BEF)), (1, rgb(0x3A2FC4)),
        ])

        context.saveGState()
        context.addPath(body)
        context.clip()
        context.drawRadialGradient(
            gradient([(0, rgb(0xFFFFFF, 0.22)), (1, rgb(0xFFFFFF, 0))]),
            startCenter: CGPoint(x: 512, y: 150), startRadius: 0,
            endCenter: CGPoint(x: 512, y: 150), endRadius: 560, options: []
        )
        context.restoreGState()

        // A faint rim light along the top edge, fading out towards the bottom.
        let rim = body.copy(strokingWithWidth: 4, lineCap: .butt, lineJoin: .round, miterLimit: 10)
        fill(context, rim, top: bodyRect.minY, bottom: bodyRect.maxY, [
            (0, rgb(0xFFFFFF, 0.35)), (0.35, rgb(0xFFFFFF, 0.06)), (1, rgb(0xFFFFFF, 0)),
        ])
    }

    // A second sheet, turned slightly, hints at the original behind the corrected text.
    func drawBackSheet(_ context: CGContext) {
        context.saveGState()
        context.translateBy(x: paperRect.midX, y: paperRect.midY)
        context.rotate(by: -.pi / 30)
        context.translateBy(x: -paperRect.midX, y: -paperRect.midY)
        let sheet = continuousRoundedRect(paperRect, radius: paperRadius)
        setShadow(context, y: 10, blur: 30, color: rgb(0x10124A, 0.30))
        context.addPath(sheet)
        context.setFillColor(rgb(0xDCE3F2))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        fill(context, sheet, top: paperRect.minY, bottom: paperRect.maxY, [(0, rgb(0xE6EBF6)), (1, rgb(0xD3DBEE))])
        context.restoreGState()
    }

    func drawPaper(_ context: CGContext) {
        let paper = continuousRoundedRect(paperRect, radius: paperRadius)

        context.saveGState()
        setShadow(context, y: 16, blur: 40, color: rgb(0x10124A, 0.40))
        context.addPath(paper)
        context.setFillColor(rgb(0xFFFFFF))
        context.fillPath()
        context.restoreGState()

        fill(context, paper, top: paperRect.minY, bottom: paperRect.maxY, [(0, rgb(0xFFFFFF)), (1, rgb(0xEDF0F6))])
    }

    func drawLines(_ context: CGContext) {
        let left = paperRect.minX + 68
        let right = paperRect.maxX - 68
        let first = letterCenter.y + letterRadius + 84
        let second = first + 62

        context.saveGState()
        context.setLineCap(.round)
        context.setLineWidth(28)
        context.setStrokeColor(rgb(0xCBD1DC))
        context.addPath(polyline(CGPoint(x: left, y: first), CGPoint(x: left + 120, y: first)))
        context.addPath(polyline(CGPoint(x: left + 312, y: first), CGPoint(x: right, y: first)))
        context.addPath(polyline(CGPoint(x: left, y: second), CGPoint(x: right - 100, y: second)))
        context.strokePath()

        // A corrected word, highlighted the way the app marks replacements.
        context.setStrokeColor(rgb(0x9BE3AF))
        context.addPath(polyline(CGPoint(x: left + 162, y: first), CGPoint(x: left + 270, y: first)))
        context.strokePath()
        context.restoreGState()
    }

    // A geometric lowercase "e": crossbar, then the bowl drawn from 3 o'clock over the top to an open tail.
    func drawLetter(_ context: CGContext) {
        let c = letterCenter, r = letterRadius
        let e = CGMutablePath()
        e.move(to: CGPoint(x: c.x - r, y: c.y))
        e.addLine(to: CGPoint(x: c.x + r, y: c.y))
        e.addArc(center: c, radius: r, startAngle: 0, endAngle: -.pi * 1.76, clockwise: true)

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(r * 0.44)
        context.setStrokeColor(rgb(0x1C2138))
        context.addPath(e)
        context.strokePath()
        context.restoreGState()
    }

    // The acute accent is a check mark whose long stroke has the accent's slant.
    func drawCheckAccent(_ context: CGContext) {
        let c = letterCenter, r = letterRadius
        let vertex = CGPoint(x: c.x + 0.16 * r, y: c.y - 1.70 * r)
        let check = polyline(
            CGPoint(x: vertex.x - 0.34 * r, y: vertex.y - 0.30 * r),
            vertex,
            CGPoint(x: vertex.x + 0.72 * r, y: vertex.y - 0.94 * r)
        )

        let stroke = check.copy(strokingWithWidth: r * 0.40, lineCap: .round, lineJoin: .round, miterLimit: 10)
        fill(context, stroke, top: vertex.y - r * 1.2, bottom: vertex.y + r * 0.2, [
            (0, rgb(0x3FD467)), (1, rgb(0x1E9E48)),
        ])
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

let fileManager = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let arguments = Array(CommandLine.arguments.dropFirst())

if let flag = arguments.firstIndex(of: "--preview") {
    guard flag + 1 < arguments.count else {
        FileHandle.standardError.write(Data("usage: make-icon.swift [--preview DIR]\n".utf8))
        exit(2)
    }
    let directory = URL(fileURLWithPath: arguments[flag + 1])
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    for pixels in [1024, 256, 64, 32, 16] {
        try writePNG(IconRenderer(pixels: pixels).render(), to: directory.appendingPathComponent("icon-\(pixels).png"))
    }
    print("Wrote previews to \(directory.path)")
}

let work = fileManager.temporaryDirectory.appendingPathComponent("corrector-icon-\(UUID().uuidString)")
let iconset = work.appendingPathComponent("AppIcon.iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try writePNG(IconRenderer(pixels: points * factor).render(), to: iconset.appendingPathComponent(name))
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
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed with status \(iconutil.terminationStatus)\n".utf8))
    exit(1)
}
print("Wrote \(output.path)")
