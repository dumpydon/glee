// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import GleeCore
import SwiftUI

/// AppKit validates each edit before displaying it, including paste and replacements.
@MainActor
struct DurationNumberField: NSViewRepresentable {
    @Binding var text: String
    let label: String
    let maximum: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.placeholderString = "0"
        field.usesSingleLineMode = true
        let font = NSFont.monospacedDigitSystemFont(ofSize: 38, weight: .light)
        field.font = font.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: 38) } ?? font
        field.formatter = context.coordinator.formatter
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.formatter.maximum = maximum
        if field.stringValue != text { field.stringValue = text }
        field.setAccessibilityLabel(label)
        let hint = maximum == 0 ? "Minutes must be zero at the 24-hour limit." : "Whole numbers from 0 to \(maximum)."
        field.setAccessibilityHelp(hint)
        field.toolTip = hint
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DurationNumberField
        let formatter = DurationComponentFormatter()

        init(_ parent: DurationNumberField) {
            self.parent = parent
            formatter.maximum = parent.maximum
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            // Keep programmatic accessibility edits under the same constraints.
            if DurationDraft.acceptsComponent(field.stringValue, maximum: parent.maximum) {
                parent.text = field.stringValue
            }
            if field.stringValue != parent.text { field.stringValue = parent.text }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}

final class DurationComponentFormatter: Formatter, @unchecked Sendable {
    var maximum = 59

    override func string(for object: Any?) -> String? { object as? String }

    override func getObjectValue(_ object: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        guard DurationDraft.acceptsComponent(string, maximum: maximum) else { return false }
        object?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(_ partialString: String,
                                      newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                      errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        DurationDraft.acceptsComponent(partialString, maximum: maximum)
    }
}
