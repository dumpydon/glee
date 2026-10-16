#!/usr/bin/env bash
# Source from build/check scripts. Never change xcode-select or shell profiles.
GLEE_SWIFT_COMMAND="${GLEE_SWIFT_EXEC:-$(command -v swift)}"
if [[ "$GLEE_SWIFT_COMMAND" == "/usr/bin/swift" ]]; then
  # SwiftPM locates compiler macro plug-ins relative to SWIFT_EXEC. Apple's
  # /usr/bin wrapper is not the selected Xcode toolchain's installation path.
  if GLEE_SELECTED_SWIFT="$(/usr/bin/xcrun --find swift 2>/dev/null)"; then
    GLEE_SWIFT_COMMAND="$GLEE_SELECTED_SWIFT"
  fi
fi
if ! "$GLEE_SWIFT_COMMAND" --version | head -1 | /usr/bin/grep -Eq 'Swift version ([6-9]|[1-9][0-9])\.'; then
  for GLEE_TOOLCHAIN_SWIFT in "$HOME"/Library/Developer/Toolchains/*.xctoolchain/usr/bin/swift; do
    [[ -x "$GLEE_TOOLCHAIN_SWIFT" ]] || continue
    if "$GLEE_TOOLCHAIN_SWIFT" --version | head -1 | /usr/bin/grep -Eq 'Swift version ([6-9]|[1-9][0-9])\.'; then
      GLEE_SWIFT_COMMAND="$GLEE_TOOLCHAIN_SWIFT"
      break
    fi
  done
fi
if ! "$GLEE_SWIFT_COMMAND" --version | head -1 | /usr/bin/grep -Eq 'Swift version ([6-9]|[1-9][0-9])\.'; then
  echo "Glee needs Swift 6 or newer. Install Xcode or a toolchain from https://www.swift.org/install/macos/." >&2
  echo "You can select an existing compiler with GLEE_SWIFT_EXEC=/absolute/path/to/usr/bin/swift." >&2
  return 2
fi
export PATH="$(dirname "$GLEE_SWIFT_COMMAND"):$PATH"
export SWIFT_EXEC="$(dirname "$GLEE_SWIFT_COMMAND")/swiftc"
export SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
