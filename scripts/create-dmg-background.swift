#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: create-dmg-background.swift <output.png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvasSize = NSSize(width: 720, height: 500)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Unable to create DMG background canvas\n", stderr)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let canvas = NSRect(origin: .zero, size: canvasSize)
NSGradient(colors: [
    NSColor(red: 0.025, green: 0.045, blue: 0.10, alpha: 1),
    NSColor(red: 0.055, green: 0.13, blue: 0.25, alpha: 1)
])!.draw(in: canvas, angle: 90)

NSGradient(colors: [
    NSColor(red: 0.02, green: 0.62, blue: 1, alpha: 0.24),
    NSColor(red: 0.02, green: 0.62, blue: 1, alpha: 0)
])!.draw(
    fromCenter: NSPoint(x: 595, y: 440),
    radius: 0,
    toCenter: NSPoint(x: 595, y: 440),
    radius: 310,
    options: [.drawsAfterEndingLocation]
)

NSColor.white.withAlphaComponent(0.035).setStroke()
let grid = NSBezierPath()
grid.lineWidth = 0.5
for x in stride(from: CGFloat(0), through: canvasSize.width, by: 32) {
    grid.move(to: NSPoint(x: x, y: 0))
    grid.line(to: NSPoint(x: x, y: canvasSize.height))
}
for y in stride(from: CGFloat(0), through: canvasSize.height, by: 32) {
    grid.move(to: NSPoint(x: 0, y: y))
    grid.line(to: NSPoint(x: canvasSize.width, y: y))
}
grid.stroke()

let logoRect = NSRect(x: 48, y: 417, width: 42, height: 42)
let logoPath = NSBezierPath(roundedRect: logoRect, xRadius: 11, yRadius: 11)
NSGradient(colors: [
    NSColor(red: 0.04, green: 0.59, blue: 1, alpha: 1),
    NSColor(red: 0.02, green: 0.34, blue: 0.94, alpha: 1)
])!.draw(in: logoPath, angle: 90)

if let logo = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: nil) {
    let configuration = NSImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
    logo.withSymbolConfiguration(configuration)?.draw(
        in: NSRect(x: 59, y: 428, width: 20, height: 20),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
}

let titleStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 25, weight: .bold),
    .foregroundColor: NSColor.white
]
let subtitleStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.62)
]
let instructionStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
    .foregroundColor: NSColor.white.withAlphaComponent(0.9)
]
NSAttributedString(string: "StillMotion", attributes: titleStyle)
    .draw(at: NSPoint(x: 104, y: 433))
NSAttributedString(string: "Native video wallpapers for macOS", attributes: subtitleStyle)
    .draw(at: NSPoint(x: 105, y: 416))

let instruction = NSAttributedString(string: "Drag StillMotion to Applications", attributes: instructionStyle)
instruction.draw(at: NSPoint(x: (canvasSize.width - instruction.size().width) / 2, y: 366))

let arrow = NSBezierPath()
arrow.lineWidth = 2
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 293, y: 290))
arrow.line(to: NSPoint(x: 427, y: 290))
arrow.move(to: NSPoint(x: 417, y: 299))
arrow.line(to: NSPoint(x: 427, y: 290))
arrow.line(to: NSPoint(x: 417, y: 281))
NSColor(red: 0.20, green: 0.72, blue: 1, alpha: 0.7).setStroke()
arrow.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to render DMG background\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL)
