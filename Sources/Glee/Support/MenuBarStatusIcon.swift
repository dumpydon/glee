// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit

/// A dedicated native glyph avoids shrinking the padded full-color app artwork.
/// Template rendering follows the menu bar: white on dark, dark on light.
@MainActor enum MenuBarStatusIcon {
    static func make(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: active ? 32 : 24, height: 20), flipped: false) { _ in
            NSColor.white.setFill()
            drawSaucer()
            drawLiquid()
            if active {
                NSBezierPath(ovalIn: NSRect(x: 27, y: 8.5, width: 3, height: 3)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    nonisolated private static func drawSaucer() {
        let saucer = NSBezierPath()
        saucer.move(to: NSPoint(x: 4.3, y: 14.6))
        saucer.curve(to: NSPoint(x: 8.8, y: 16.4), controlPoint1: NSPoint(x: 4.3, y: 15.5), controlPoint2: NSPoint(x: 6.4, y: 16.1))
        saucer.curve(to: NSPoint(x: 12, y: 19), controlPoint1: NSPoint(x: 9.1, y: 18), controlPoint2: NSPoint(x: 10.4, y: 19))
        saucer.curve(to: NSPoint(x: 15.2, y: 16.4), controlPoint1: NSPoint(x: 13.6, y: 19), controlPoint2: NSPoint(x: 14.9, y: 18))
        saucer.curve(to: NSPoint(x: 19.7, y: 14.6), controlPoint1: NSPoint(x: 17.6, y: 16.1), controlPoint2: NSPoint(x: 19.7, y: 15.5))
        saucer.curve(to: NSPoint(x: 14, y: 12.9), controlPoint1: NSPoint(x: 19.7, y: 13.7), controlPoint2: NSPoint(x: 17.2, y: 13.1))
        saucer.line(to: NSPoint(x: 13, y: 12.1))
        saucer.line(to: NSPoint(x: 11, y: 12.1))
        saucer.line(to: NSPoint(x: 10, y: 12.9))
        saucer.curve(to: NSPoint(x: 4.3, y: 14.6), controlPoint1: NSPoint(x: 6.8, y: 13.1), controlPoint2: NSPoint(x: 4.3, y: 13.7))
        saucer.close()
        for x in [7.5, 11.3, 15.1] {
            saucer.append(NSBezierPath(ovalIn: NSRect(x: x, y: 14, width: 1.4, height: 1)))
        }
        saucer.windingRule = .evenOdd
        saucer.fill()
    }

    nonisolated private static func drawLiquid() {
        let pool = NSBezierPath()
        pool.move(to: NSPoint(x: 1, y: 4.7))
        pool.curve(to: NSPoint(x: 5.2, y: 6.6), controlPoint1: NSPoint(x: 0.6, y: 6.5), controlPoint2: NSPoint(x: 3.2, y: 7.2))
        pool.curve(to: NSPoint(x: 7.3, y: 7.9), controlPoint1: NSPoint(x: 6.8, y: 6), controlPoint2: NSPoint(x: 5.7, y: 8.7))
        pool.curve(to: NSPoint(x: 9.7, y: 7.1), controlPoint1: NSPoint(x: 8.1, y: 7.7), controlPoint2: NSPoint(x: 8.6, y: 7))
        pool.curve(to: NSPoint(x: 12, y: 11), controlPoint1: NSPoint(x: 11.3, y: 7.5), controlPoint2: NSPoint(x: 10.7, y: 11))
        pool.curve(to: NSPoint(x: 14.3, y: 7.1), controlPoint1: NSPoint(x: 13.3, y: 11), controlPoint2: NSPoint(x: 12.7, y: 7.5))
        pool.curve(to: NSPoint(x: 17.4, y: 7.7), controlPoint1: NSPoint(x: 15.7, y: 6.5), controlPoint2: NSPoint(x: 15.7, y: 8.6))
        pool.curve(to: NSPoint(x: 18.9, y: 6.1), controlPoint1: NSPoint(x: 18.8, y: 7), controlPoint2: NSPoint(x: 17.2, y: 6.1))
        pool.curve(to: NSPoint(x: 23, y: 4.6), controlPoint1: NSPoint(x: 21.6, y: 6.7), controlPoint2: NSPoint(x: 23.4, y: 5.7))
        pool.curve(to: NSPoint(x: 19.5, y: 3.6), controlPoint1: NSPoint(x: 22.7, y: 3.5), controlPoint2: NSPoint(x: 20.7, y: 4))
        pool.curve(to: NSPoint(x: 20.1, y: 1.4), controlPoint1: NSPoint(x: 18, y: 3.2), controlPoint2: NSPoint(x: 21.3, y: 2.8))
        pool.curve(to: NSPoint(x: 14.8, y: 1.7), controlPoint1: NSPoint(x: 18.6, y: 0.1), controlPoint2: NSPoint(x: 17, y: 1.5))
        pool.curve(to: NSPoint(x: 11.2, y: 2.7), controlPoint1: NSPoint(x: 12.9, y: 1.9), controlPoint2: NSPoint(x: 13.1, y: 3.5))
        pool.curve(to: NSPoint(x: 6.4, y: 1.2), controlPoint1: NSPoint(x: 9.5, y: 2), controlPoint2: NSPoint(x: 8.5, y: 0.2))
        pool.curve(to: NSPoint(x: 4.9, y: 3.5), controlPoint1: NSPoint(x: 3.8, y: 2.4), controlPoint2: NSPoint(x: 7, y: 3.2))
        pool.curve(to: NSPoint(x: 1, y: 4.7), controlPoint1: NSPoint(x: 2.9, y: 3.9), controlPoint2: NSPoint(x: 1.2, y: 3.5))
        pool.close()
        // A broad transparent liquid highlight survives at actual status size.
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: 4.4, y: 4.8))
        highlight.curve(to: NSPoint(x: 11.8, y: 8.8), controlPoint1: NSPoint(x: 8.8, y: 4), controlPoint2: NSPoint(x: 10.2, y: 6.8))
        highlight.curve(to: NSPoint(x: 5.2, y: 5.6), controlPoint1: NSPoint(x: 11.2, y: 5.6), controlPoint2: NSPoint(x: 8.5, y: 4.7))
        highlight.curve(to: NSPoint(x: 4.4, y: 4.8), controlPoint1: NSPoint(x: 4.3, y: 5.8), controlPoint2: NSPoint(x: 3.9, y: 5.3))
        highlight.close()
        pool.append(highlight)
        pool.windingRule = .evenOdd
        pool.fill()
    }
}
