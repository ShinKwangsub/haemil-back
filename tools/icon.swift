// 앱 아이콘(AppIcon.icns)을 그린다: 둥근 사각형 바탕 위에 마우스와 뒤로 화살표.
// 사용: swift tools/icon.swift   (저장소 맨 위에서)
import AppKit

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // 맥 아이콘 격자: 1024 안에 824 크기 둥근 사각형
    let inset = s * 100 / 1024
    let card = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: card, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGradient(starting: NSColor(red: 0.16, green: 0.42, blue: 0.95, alpha: 1),
               ending: NSColor(red: 0.08, green: 0.18, blue: 0.55, alpha: 1))!.draw(in: bg, angle: -90)

    NSColor.white.setStroke()
    NSColor.white.setFill()
    let line = s * 34 / 1024

    // 마우스 몸통과 가운데 줄
    let body = NSRect(x: s * 0.50, y: s * 0.24, width: s * 0.26, height: s * 0.44)
    let mouse = NSBezierPath(roundedRect: body, xRadius: body.width / 2, yRadius: body.width / 2)
    mouse.lineWidth = line
    mouse.stroke()
    let mid = NSBezierPath()
    mid.move(to: NSPoint(x: body.midX, y: body.maxY))
    mid.line(to: NSPoint(x: body.midX, y: body.maxY - body.height * 0.32))
    mid.lineWidth = line
    mid.stroke()
    // 옆 버튼 두 개
    for y in [0.43, 0.51] {
        NSBezierPath(roundedRect: NSRect(x: body.minX - s * 0.045, y: s * y, width: s * 0.05, height: s * 0.06),
                     xRadius: s * 0.015, yRadius: s * 0.015).fill()
    }
    // 뒤로 화살표
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: s * 0.38, y: s * 0.62))
    arrow.line(to: NSPoint(x: s * 0.24, y: s * 0.48))
    arrow.line(to: NSPoint(x: s * 0.38, y: s * 0.34))
    arrow.lineWidth = s * 52 / 1024
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try! draw(pt).write(to: set.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try! draw(pt * 2).write(to: set.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "AppIcon.icns"]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "AppIcon.icns 를 만들었습니다" : "iconutil 실패")
