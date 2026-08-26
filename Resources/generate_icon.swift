import AppKit

func renderAppIcon(size: Int) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let S = CGFloat(size)
    let margin = S * 0.08
    let squircleRect = NSRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
    let cornerRadius = S * 0.22
    let bgPath = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(colors: [NSColor(red: 0.18, green: 0.86, blue: 0.45, alpha: 1.0), NSColor(red: 0.04, green: 0.62, blue: 0.32, alpha: 1.0)])!
    gradient.draw(in: bgPath, angle: -45)
    bgPath.lineWidth = S * 0.015
    NSColor.white.withAlphaComponent(0.25).setStroke()
    bgPath.stroke()
    
    let bubbleCenter = NSPoint(x: S * 0.46, y: S * 0.54)
    let bubbleRadius = S * 0.24
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -S * 0.02)
    shadow.shadowBlurRadius = S * 0.04
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.set()
    let bubble = NSBezierPath()
    bubble.appendArc(withCenter: bubbleCenter, radius: bubbleRadius, startAngle: 0, endAngle: 360)
    bubble.move(to: NSPoint(x: bubbleCenter.x - bubbleRadius * 0.70, y: bubbleCenter.y - bubbleRadius * 0.65))
    bubble.line(to: NSPoint(x: bubbleCenter.x - bubbleRadius * 1.15, y: bubbleCenter.y - bubbleRadius * 1.05))
    bubble.line(to: NSPoint(x: bubbleCenter.x - bubbleRadius * 0.25, y: bubbleCenter.y - bubbleRadius * 0.95))
    bubble.close()
    NSColor.white.set()
    bubble.fill()
    
    if let phone = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: nil) {
        let pSize = S * 0.24
        let pRect = NSRect(x: bubbleCenter.x - pSize/2, y: bubbleCenter.y - pSize/2, width: pSize/2, height: pSize)
        let pColor = NSColor(red: 0.06, green: 0.70, blue: 0.36, alpha: 1.0)
        let tintedPhone = NSImage(size: NSSize(width: pSize, height: pSize))
        tintedPhone.lockFocus()
        pColor.set()
        NSRect(origin: .zero, size: tintedPhone.size).fill()
        phone.draw(in: NSRect(origin: .zero, size: tintedPhone.size), from: .zero, operation: .destinationIn, fraction: 1.0)
        tintedPhone.unlockFocus()
        tintedPhone.draw(in: pRect)
    }
    
    let broomShadow = NSShadow()
    broomShadow.shadowOffset = NSSize(width: S * 0.02, height: -S * 0.03)
    broomShadow.shadowBlurRadius = S * 0.05
    broomShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    broomShadow.set()
    if let broom = NSImage(systemSymbolName: "broom.fill", accessibilityDescription: nil) {
        let bSize = S * 0.52
        let broomImg = NSImage(size: NSSize(width: bSize, height: bSize))
        broomImg.lockFocus()
        NSColor(red: 1.0, green: 0.84, blue: 0.28, alpha: 1.0).set()
        NSRect(origin: .zero, size: broomImg.size).fill()
        broom.draw(in: NSRect(origin: .zero, size: broomImg.size), from: .zero, operation: .destinationIn, fraction: 1.0)
        broomImg.unlockFocus()
        broomImg.draw(in: NSRect(x: S * 0.36, y: S * 0.14, width: bSize, height: bSize))
    }
    
    if let sparkles = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) {
        let sSize = S * 0.24
        let sImg = NSImage(size: NSSize(width: sSize, height: sSize))
        sImg.lockFocus()
        NSColor.white.set()
        NSRect(origin: .zero, size: sImg.size).fill()
        sparkles.draw(in: NSRect(origin: .zero, size: sImg.size), from: .zero, operation: .destinationIn, fraction: 1.0)
        sImg.unlockFocus()
        sImg.draw(in: NSRect(x: S * 0.66, y: S * 0.66, width: sSize, height: sSize))
    }
    NSGraphicsContext.restoreGraphicsState()
    let resultImage = NSImage(size: NSSize(width: size, height: size))
    resultImage.addRepresentation(rep)
    return resultImage
}

let icon = renderAppIcon(size: 1024)
let appDirs = [
    URL(fileURLWithPath: "/Applications/WhatsClean.app"),
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/WhatsClean.app"),
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/WhatsClean/WhatsClean.app")
]

for appURL in appDirs {
    if FileManager.default.fileExists(atPath: appURL.path) {
        _ = NSWorkspace.shared.setIcon(icon, forFile: appURL.path, options: [])
    }
}
