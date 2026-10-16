#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/script/swift_environment.sh"
# These suites use Swift Testing. CLT-only Macs do not include XCTest's platform.
swift test --disable-sandbox --disable-xctest --enable-swift-testing
python3 -m unittest discover -s script -p 'test_*.py'
