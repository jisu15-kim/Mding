#!/usr/bin/env swift
// DMG 배경 이미지 생성기 — scripts/dmg-assets/ 에 1x·2x PNG 를 쓴다.
// 좌표계는 bottom-left 원점. create-dmg 아이콘 배치(top 기준 y=190)와 맞춰
// 화살표를 y=230(=420-190) 높이에 그린다.
import AppKit

let W: CGFloat = 660
let H: CGFloat = 420
let outDir = "scripts/dmg-assets"

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (scale, name) in [(CGFloat(1), "dmg-background.png"), (CGFloat(2), "dmg-background@2x.png")] {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: W, height: H)  // 포인트 크기 → 2x 는 144dpi 메타데이터

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // 배경: 아주 옅은 세로 그라데이션
    let gradient = NSGradient(
        starting: NSColor(calibratedWhite: 0.93, alpha: 1),
        ending: NSColor(calibratedWhite: 0.975, alpha: 1)
    )!
    gradient.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

    // 화살표: 앱 아이콘(중심 x=165)과 Applications(중심 x=495) 사이
    let arrowColor = NSColor(calibratedWhite: 0.74, alpha: 1)
    let y: CGFloat = 230
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 258, y: y))
    shaft.line(to: NSPoint(x: 384, y: y))
    shaft.lineWidth = 7
    shaft.lineCapStyle = .round
    arrowColor.setStroke()
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: 380, y: y + 13))
    head.line(to: NSPoint(x: 402, y: y))
    head.line(to: NSPoint(x: 380, y: y - 13))
    head.lineWidth = 7
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    arrowColor.setStroke()
    head.stroke()

    // 상단 워드마크
    let titleFont = NSFont.systemFont(ofSize: 23, weight: .semibold)
    let roundedFont = NSFont(
        descriptor: titleFont.fontDescriptor.withDesign(.rounded) ?? titleFont.fontDescriptor,
        size: 23
    ) ?? titleFont
    let title = NSAttributedString(string: "Mding", attributes: [
        .font: roundedFont,
        .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1),
    ])
    title.draw(at: NSPoint(x: (W - title.size().width) / 2, y: 352))

    let subtitle = NSAttributedString(string: "Markdown viewer & editor", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1),
    ])
    subtitle.draw(at: NSPoint(x: (W - subtitle.size().width) / 2, y: 332))

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("✓ \(outDir)/\(name)")
}
