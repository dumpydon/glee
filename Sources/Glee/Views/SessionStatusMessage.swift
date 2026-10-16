// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

@MainActor
struct SessionStatusMessage: View {
    let message: String?
    let attentionTrigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Keep the animator mounted even before the first blocked attempt.
        VStack(spacing: 0) {
            if let message {
                Label(message, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 22)
            }
        }
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: attentionTrigger) { [reduceMotion] content, offset in
            content.offset(x: reduceMotion ? 0 : offset)
        } keyframes: { _ in
            CubicKeyframe(-5, duration: 0.06)
            CubicKeyframe(5, duration: 0.08)
            CubicKeyframe(-3, duration: 0.07)
            CubicKeyframe(3, duration: 0.06)
            CubicKeyframe(0, duration: 0.09)
        }
    }
}
