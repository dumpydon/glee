#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Glee"
BUNDLE_ID="com.dumpydon.glee"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${GLEE_DESTINATION:-$ROOT_DIR/dist/$APP_NAME.app}"
CONFIGURATION="${GLEE_BUILD_CONFIGURATION:-debug}"
case "$CONFIGURATION" in debug|release) ;; *) echo "Invalid build configuration" >&2; exit 2 ;; esac
mkdir -p "$ROOT_DIR/dist"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/dist/.Glee-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_BINARY="$APP_CONTENTS/MacOS/$APP_NAME"

# A local certificate fingerprint is not a private key. Keep the selection out
# of Git and allow an explicit environment override (including '-' for ad hoc).
if [[ -n "${GLEE_SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$GLEE_SIGN_IDENTITY"
elif [[ -s "$ROOT_DIR/.signing-identity" ]]; then
  SIGN_IDENTITY="$(cat "$ROOT_DIR/.signing-identity")"
else
  SIGN_IDENTITY="-"
fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  export GLEE_ENABLE_SPARKLE=0
else
  export GLEE_ENABLE_SPARKLE=1
fi

case "$MODE" in
  run|--build-only|--verify|--logs|--telemetry|--debug) ;;
  *) echo "Usage: $0 [--build-only|--verify|--logs|--telemetry|--debug]" >&2; exit 2 ;;
esac

cd "$ROOT_DIR"
source "$ROOT_DIR/script/swift_environment.sh"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

if [[ "$MODE" != "--build-only" ]]; then
  # Stop only Glee; other applications have independent lifecycles.
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
else
  python3 "$ROOT_DIR/script/check_build_destination.py" "$DESTINATION/Contents/MacOS/$APP_NAME"
fi

BUILD_ARGS=(--disable-sandbox --configuration "$CONFIGURATION")
if [[ "${GLEE_UNIVERSAL:-0}" == "1" ]]; then BUILD_ARGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_ARGS[@]}"
BUILD_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
if [[ "$GLEE_ENABLE_SPARKLE" == "1" ]]; then
  SPARKLE_ROOT="$ROOT_DIR/.build/artifacts/sparkle/Sparkle"
  SPARKLE_FRAMEWORK="$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
  [[ -d "$SPARKLE_FRAMEWORK" ]] || { echo "Sparkle framework is missing" >&2; exit 1; }
fi

if [[ ! -f "$ROOT_DIR/Resources/Glee.icns" || "${GLEE_REGENERATE_ICON:-0}" == "1" ]]; then
  swiftc "$ROOT_DIR/script/create_icon.swift" -o "$ROOT_DIR/.build/glee-create-icon"
  "$ROOT_DIR/.build/glee-create-icon" "$ROOT_DIR/.build/Glee.iconset"
  iconutil -c icns "$ROOT_DIR/.build/Glee.iconset" -o "$ROOT_DIR/Resources/Glee.icns"
fi

mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources" "$APP_CONTENTS/Library/HelperTools" "$APP_CONTENTS/Library/LaunchDaemons"
mkdir -p "$APP_CONTENTS/Frameworks"
if [[ "$GLEE_ENABLE_SPARKLE" == "1" ]]; then
  /usr/bin/ditto "$SPARKLE_FRAMEWORK" "$APP_CONTENTS/Frameworks/Sparkle.framework"
  cp "$SPARKLE_ROOT/LICENSE" "$APP_CONTENTS/Resources/Sparkle-LICENSE.txt"
fi
cp "$ROOT_DIR/LICENSE" "$APP_CONTENTS/Resources/Glee-LICENSE.txt"
cp "$ROOT_DIR/NOTICE" "$APP_CONTENTS/Resources/Glee-NOTICE.txt"
cp "$ROOT_DIR/script/build_local_helper_pkg.py" "$APP_CONTENTS/Resources/"
cp "$BUILD_DIR/$APP_NAME" "$APP_BINARY"
cp "$BUILD_DIR/GleeHelper" "$APP_CONTENTS/Library/HelperTools/GleeHelper"
cp "$ROOT_DIR/Resources/com.dumpydon.glee.helper.plist" "$APP_CONTENTS/Library/LaunchDaemons/"
cp "$ROOT_DIR/Resources/Glee.icns" "$APP_CONTENTS/Resources/"
chmod +x "$APP_BINARY"

# Swift.org SwiftPM can embed its local Swift Testing search path even in a
# release executable. Neither shipping executable uses that library. Remove
# the developer-specific path before signing; keep all runtime system paths.
python3 - "$APP_BINARY" "$APP_CONTENTS/Library/HelperTools/GleeHelper" <<'PYTHON'
import subprocess
import sys
for executable in sys.argv[1:]:
    load_commands = subprocess.run(["/usr/bin/otool", "-l", executable],
                                  check=True, capture_output=True, text=True).stdout
    is_rpath = False
    for line in load_commands.splitlines():
        line = line.strip()
        if line.startswith("cmd "):
            is_rpath = line == "cmd LC_RPATH"
        if is_rpath and line.startswith("path "):
            path = line[5:].rsplit(" (offset ", 1)[0]
            if path.endswith("/swift/macosx/testing"):
                subprocess.run(["/usr/bin/install_name_tool", "-delete_rpath", path, executable], check=True)
PYTHON

cp "$ROOT_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
/usr/bin/plutil -lint "$APP_CONTENTS/Info.plist"

# Sign nested executable code first. Ad-hoc clients require administrator-installed pins.
SIGN_OPTIONS=(--force --sign "$SIGN_IDENTITY" --options runtime)
if [[ "$SIGN_IDENTITY" != "-" ]]; then SIGN_OPTIONS+=(--timestamp); fi
# Sign from the inside out, preserving Sparkle's framework symlinks and the
# XPC services' existing sandbox entitlements. Never use --deep for signing.
if [[ "$GLEE_ENABLE_SPARKLE" == "1" ]]; then
  SPARKLE_VERSION="$APP_CONTENTS/Frameworks/Sparkle.framework/Versions/B"
  for SERVICE in "$SPARKLE_VERSION"/XPCServices/*.xpc; do
    codesign "${SIGN_OPTIONS[@]}" --preserve-metadata=entitlements "$SERVICE"
  done
  codesign "${SIGN_OPTIONS[@]}" "$SPARKLE_VERSION/Autoupdate"
  codesign "${SIGN_OPTIONS[@]}" "$SPARKLE_VERSION/Updater.app"
  codesign "${SIGN_OPTIONS[@]}" "$APP_CONTENTS/Frameworks/Sparkle.framework"
fi
codesign "${SIGN_OPTIONS[@]}" --identifier "com.dumpydon.glee.helper" "$APP_CONTENTS/Library/HelperTools/GleeHelper"
codesign "${SIGN_OPTIONS[@]}" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

# Never expose a half-written or temporarily unsigned bundle to launchd.
# Keep the prior bundle intact until its replacement has passed signing checks.
# A running process still uses the old signed executable. Replacing its bundle
# can make SMAppService registration fail with EINVAL until that process exits.
# Check again here in case the destination was opened during the build.
python3 "$ROOT_DIR/script/check_build_destination.py" "$DESTINATION/Contents/MacOS/$APP_NAME"
mkdir -p "$(dirname "$DESTINATION")"
if [[ -e "$DESTINATION" ]]; then mv "$DESTINATION" "$STAGING_DIR/Previous.app"; fi
if ! mv "$APP_BUNDLE" "$DESTINATION"; then
  if [[ -e "$STAGING_DIR/Previous.app" ]]; then mv "$STAGING_DIR/Previous.app" "$DESTINATION"; fi
  exit 1
fi
APP_BUNDLE="$DESTINATION"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

case "$MODE" in
  --build-only) echo "Built $APP_BUNDLE" ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "Glee is running: $APP_BUNDLE"
    ;;
  --debug) lldb -- "$APP_BINARY" ;;
  --logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
esac
