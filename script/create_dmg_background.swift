// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import ImageIO
import UniformTypeIdentifiers

// A Finder background is static artwork. Actual icons, names, selection and
// dragging belong to Finder; never paint fake app or Applications controls.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let width = 520
let height = 260

func background(scale: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                  pixelsWide: width * scale, pixelsHigh: height * scale,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(scale))
    transform.concat()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // Icon coordinates in the Finder metadata use a top-left origin.
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    let y: CGFloat = 148
    arrow.move(to: NSPoint(x: 242, y: y))
    arrow.line(to: NSPoint(x: 278, y: y))
    arrow.move(to: NSPoint(x: 266, y: y + 12))
    arrow.line(to: NSPoint(x: 278, y: y))
    arrow.line(to: NSPoint(x: 266, y: y - 12))
    NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
    arrow.stroke()

    let instruction = "Drag Glee.app to Applications" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1),
    ]
    let textSize = instruction.size(withAttributes: attributes)
    instruction.draw(at: NSPoint(x: (CGFloat(width) - textSize.width) / 2, y: 24),
                     withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = NSSize(width: width, height: height)
    return bitmap
}

var representations: [NSBitmapImageRep] = []
for scale in [1, 2] {
    representations.append(background(scale: scale))
}
let provenance = "Authored vector arrow and Glee.app installation instruction on white by script/create_dmg_background.swift. Real icons and file labels are rendered by Finder."
let tiff = NSMutableData()
let destination = CGImageDestinationCreateWithData(tiff, UTType.tiff.identifier as CFString,
                                                  representations.count, nil)!
for (index, bitmap) in representations.enumerated() {
    let properties: [CFString: Any] = [
        kCGImagePropertyDPIWidth: 72 * (index + 1),
        kCGImagePropertyDPIHeight: 72 * (index + 1),
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFImageDescription: provenance],
    ]
    CGImageDestinationAddImage(destination, bitmap.cgImage!, properties as CFDictionary)
}
precondition(CGImageDestinationFinalize(destination))
try (tiff as Data).write(to: directory.appendingPathComponent("background.tiff"))
