# Glee verification

Last checked: 16 October 2026.

## Automated checks

- 149 Swift tests and 33 Python tests passed.
- Full-Xcode CI built the app and helper for both arm64 and x86_64 and verified both slices.
- Local app/helper signatures passed deep strict verification.
- Installer packages were expanded and checked for exact helper bytes, code pins, and fixed no-payload scripts.
- ZIP and DMG packaging preserved app bytes and symlinks.

## Current Mac runtime

Glee 2.0.0 build 4 was tested on an Apple silicon Mac running macOS 15.7.8.

Timer, Until, Unlimited, 15-minute extensions, display controls, settings, and manual stop were exercised. The refreshed helper installer completed successfully. Its root-owned app/helper pins matched the installed build, and authenticated closed-lid mode reached **Ready to close the lid**.

During the test, macOS reported closed-lid sleep prevention enabled and Glee's sleep assertion active. Ending the test restored normal sleep and released the assertion. The app was left idle.

An earlier build with the same session engine passed a human-reported short physical lid test. Controlled app death restored normal sleep in 0.38 seconds; a real one-minute session expired with the popover closed; a different-code-hash client was rejected.

## Scope

Runtime evidence is specific to this Mac and the named build. Four-hour endurance, real low-battery/thermal boundaries, root uninstall, Intel hardware, and a full macOS-version/accessibility matrix have not all been executed. Unit tests cover policy boundaries but do not replace hardware checks.

The local release is not Apple-notarized and uses manual updates. The launch video illustrates the interface with Liquid Glass; macOS 14/15 use native fallback controls.
