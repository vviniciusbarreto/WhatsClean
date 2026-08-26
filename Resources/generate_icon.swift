import AppKit
import CoreGraphics
import Foundation

func createIconBitmap(pixels: Int, modernCanvas: Bool = false) -> CGImage? {
    let width = pixels
    let height = pixels
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let alphaInfo: CGImageAlphaInfo = modernCanvas ? .noneSkipLast : .premultipliedLast
    let bitmapInfo = CGBitmapInfo(rawValue: alphaInfo.rawValue)

    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        return nil
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let size = CGFloat(pixels)
    let s = size / 1024.0

    // Squircle
    // Keep only a narrow optical margin. A large transparent inset makes
    // modern macOS releases place the legacy artwork inside a second tile.
    let margin: CGFloat = (modernCanvas ? 0.0 : 28.0) * s
    let rectSize: CGFloat = size - (margin * 2.0)
    let cornerRadius: CGFloat = (modernCanvas ? 0.0 : 220.0) * s
    let squircleRect = CGRect(x: margin, y: margin, width: rectSize, height: rectSize)
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    if !modernCanvas {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12.0 * s), blur: 24.0 * s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
        ctx.addPath(squirclePath)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Background Emerald Gradient
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    let bgColors = [
        CGColor(red: 0.05, green: 0.45, blue: 0.28, alpha: 1.0),
        CGColor(red: 0.12, green: 0.72, blue: 0.42, alpha: 1.0),
        CGColor(red: 0.22, green: 0.88, blue: 0.54, alpha: 1.0)
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: margin, y: margin), end: CGPoint(x: size - margin, y: size - margin), options: [])
    }

    let glowColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.22),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(glowGradient, startCenter: CGPoint(x: size * 0.75, y: size * 0.75), startRadius: 0, endCenter: CGPoint(x: size * 0.75, y: size * 0.75), endRadius: size * 0.6, options: [])
    }

    if !modernCanvas {
        let innerBorder = CGPath(roundedRect: squircleRect.insetBy(dx: 2.0 * s, dy: 2.0 * s), cornerWidth: cornerRadius - 2.0 * s, cornerHeight: cornerRadius - 2.0 * s, transform: nil)
        ctx.addPath(innerBorder)
        ctx.setLineWidth(2.5 * s)
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.35))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Central Chat Message Bubble
    let bubbleCenter = CGPoint(x: size * 0.44, y: size * 0.52)
    let bubbleWidth = 440.0 * s
    let bubbleHeight = 360.0 * s
    let bubbleRect = CGRect(x: bubbleCenter.x - bubbleWidth/2, y: bubbleCenter.y - bubbleHeight/2 + 20*s, width: bubbleWidth, height: bubbleHeight)
    let bubbleRadius = 80.0 * s

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8.0 * s), blur: 18.0 * s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))

    let bubblePath = CGMutablePath()
    bubblePath.addRoundedRect(in: bubbleRect, cornerWidth: bubbleRadius, cornerHeight: bubbleRadius)
    let tailStart = CGPoint(x: bubbleRect.minX + 50*s, y: bubbleRect.minY + 20*s)
    let tailTip = CGPoint(x: bubbleRect.minX - 35*s, y: bubbleRect.minY - 35*s)
    let tailEnd = CGPoint(x: bubbleRect.minX + 110*s, y: bubbleRect.minY)
    bubblePath.move(to: tailStart)
    bubblePath.addQuadCurve(to: tailTip, control: CGPoint(x: bubbleRect.minX - 10*s, y: bubbleRect.minY - 5*s))
    bubblePath.addQuadCurve(to: tailEnd, control: CGPoint(x: bubbleRect.minX + 40*s, y: bubbleRect.minY - 15*s))
    bubblePath.closeSubpath()

    ctx.addPath(bubblePath)
    ctx.setFillColor(CGColor(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.96))
    ctx.fillPath()

    ctx.addPath(bubblePath)
    ctx.setLineWidth(3.0 * s)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.8))
    ctx.strokePath()

    let phoneSize = 250.0 * s
    let phoneCenter = CGPoint(x: bubbleRect.midX, y: bubbleRect.midY)
    let phoneRect = CGRect(x: phoneCenter.x - phoneSize/2, y: phoneCenter.y - phoneSize/2, width: phoneSize, height: phoneSize)
    if let phoneImg = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: nil) {
        let tinted = NSImage(size: NSSize(width: phoneSize, height: phoneSize))
        tinted.lockFocus()
        NSColor(red: 0.10, green: 0.65, blue: 0.38, alpha: 1.0).set()
        NSRect(origin: .zero, size: tinted.size).fill()
        phoneImg.draw(in: NSRect(origin: .zero, size: tinted.size), from: .zero, operation: .destinationIn, fraction: 1.0)
        tinted.unlockFocus()
        if let cg = tinted.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(cg, in: phoneRect)
        }
    }
    ctx.restoreGState()

    // Stylized Cleaning Broom
    ctx.saveGState()
    let broomOrigin = CGPoint(x: size * 0.68, y: size * 0.44)
    ctx.translateBy(x: broomOrigin.x, y: broomOrigin.y)
    ctx.rotate(by: -0.58)

    ctx.setShadow(offset: CGSize(width: 6.0 * s, height: -12.0 * s), blur: 18.0 * s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.38))

    let handleWidth = 24.0 * s
    // Let the handle break the green silhouette slightly, while keeping the
    // important part inside the 1024 px canvas at every generated size.
    let handleHeight = (modernCanvas ? 430.0 : 500.0) * s
    let handleRect = CGRect(x: -handleWidth/2, y: 10*s, width: handleWidth, height: handleHeight)
    let handlePath = CGPath(roundedRect: handleRect, cornerWidth: 12.0 * s, cornerHeight: 12.0 * s, transform: nil)

    ctx.saveGState()
    ctx.addPath(handlePath)
    ctx.clip()
    let handleColors = [
        CGColor(red: 0.82, green: 0.58, blue: 0.28, alpha: 1.0),
        CGColor(red: 0.96, green: 0.80, blue: 0.48, alpha: 1.0),
        CGColor(red: 0.70, green: 0.45, blue: 0.18, alpha: 1.0)
    ] as CFArray
    if let handleGrad = CGGradient(colorsSpace: colorSpace, colors: handleColors, locations: [0.0, 0.45, 1.0]) {
        ctx.drawLinearGradient(handleGrad, start: CGPoint(x: -handleWidth/2, y: 0), end: CGPoint(x: handleWidth/2, y: 0), options: [])
    }
    ctx.restoreGState()

    let collarRect = CGRect(x: -28.0 * s, y: 0, width: 56.0 * s, height: 26.0 * s)
    let collarPath = CGPath(roundedRect: collarRect, cornerWidth: 6.0 * s, cornerHeight: 6.0 * s, transform: nil)
    ctx.addPath(collarPath)
    ctx.setFillColor(CGColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 1.0))
    ctx.fillPath()

    let bristlePath = CGMutablePath()
    bristlePath.move(to: CGPoint(x: -26.0 * s, y: 0))
    bristlePath.addLine(to: CGPoint(x: -95.0 * s, y: -190.0 * s))
    bristlePath.addQuadCurve(to: CGPoint(x: 95.0 * s, y: -190.0 * s), control: CGPoint(x: 0, y: -205.0 * s))
    bristlePath.addLine(to: CGPoint(x: 26.0 * s, y: 0))
    bristlePath.closeSubpath()

    ctx.saveGState()
    ctx.addPath(bristlePath)
    ctx.clip()
    let bristleColors = [
        CGColor(red: 0.98, green: 0.78, blue: 0.22, alpha: 1.0),
        CGColor(red: 0.90, green: 0.65, blue: 0.15, alpha: 1.0),
        CGColor(red: 0.78, green: 0.50, blue: 0.10, alpha: 1.0)
    ] as CFArray
    if let bristleGrad = CGGradient(colorsSpace: colorSpace, colors: bristleColors, locations: [0.0, 0.6, 1.0]) {
        ctx.drawLinearGradient(bristleGrad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: -190.0 * s), options: [])
    }

    ctx.setLineWidth(2.5 * s)
    ctx.setStrokeColor(CGColor(red: 0.68, green: 0.42, blue: 0.08, alpha: 0.45))
    for xOffset in [-60, -40, -20, 0, 20, 40, 60] {
        let x = CGFloat(xOffset) * s
        ctx.move(to: CGPoint(x: x * 0.28, y: -10 * s))
        ctx.addLine(to: CGPoint(x: x, y: -185 * s))
        ctx.strokePath()
    }
    ctx.restoreGState()

    ctx.addPath(bristlePath)
    ctx.setLineWidth(2.0 * s)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 0.90, blue: 0.50, alpha: 0.6))
    ctx.strokePath()
    ctx.restoreGState()

    // Radiant Magic Sparkles ✨
    func drawSparkle(center: CGPoint, radius: CGFloat, haloColor: CGColor) {
        ctx.saveGState()
        let haloGradColors = [haloColor, CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)] as CFArray
        if let hg = CGGradient(colorsSpace: colorSpace, colors: haloGradColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(hg, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius * 1.6, options: [])
        }

        let starPath = CGMutablePath()
        starPath.move(to: CGPoint(x: center.x, y: center.y + radius))
        starPath.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + radius*0.25, y: center.y + radius*0.25))
        starPath.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x + radius*0.25, y: center.y - radius*0.25))
        starPath.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - radius*0.25, y: center.y - radius*0.25))
        starPath.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x - radius*0.25, y: center.y + radius*0.25))
        starPath.closeSubpath()

        ctx.setShadow(offset: .zero, blur: 10 * s, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
        ctx.addPath(starPath)
        ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.98))
        ctx.fillPath()
        ctx.restoreGState()
    }

    drawSparkle(center: CGPoint(x: size * 0.76, y: size * 0.74), radius: 46 * s, haloColor: CGColor(red: 0.35, green: 0.95, blue: 0.85, alpha: 0.45))
    drawSparkle(center: CGPoint(x: size * 0.84, y: size * 0.32), radius: 34 * s, haloColor: CGColor(red: 1.0, green: 0.90, blue: 0.40, alpha: 0.45))
    drawSparkle(center: CGPoint(x: size * 0.24, y: size * 0.72), radius: 28 * s, haloColor: CGColor(red: 0.50, green: 1.0, blue: 0.70, alpha: 0.4))

    return ctx.makeImage()
}

func saveCGImageAsPNG(image: CGImage, path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outputPath = CommandLine.arguments.dropFirst().first
        ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/AppIcon.png").path
let modernOutputPath = CommandLine.arguments.dropFirst(2).first
        ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/AppIconModern.png").path

if let img = createIconBitmap(pixels: 1024) {
    saveCGImageAsPNG(image: img, path: outputPath)
    print("Icon generated at \(outputPath)")
}

if let modernImg = createIconBitmap(pixels: 1024, modernCanvas: true) {
    saveCGImageAsPNG(image: modernImg, path: modernOutputPath)
    print("Modern icon generated at \(modernOutputPath)")
}
