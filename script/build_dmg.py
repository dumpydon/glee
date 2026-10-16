#!/usr/bin/env python3
"""Package an already notarized release app in the native Finder installer.

Install the packaging dependency once:
  npm install --prefix .build/dmg-tools --no-audit --no-fund appdmg@0.6.6

Build and inspect, then notarize the final image:
  python3 script/build_dmg.py build dist/updates/<version>-<build>
  python3 script/build_dmg.py notarize dist/updates/<version>-<build> --notary-profile "$(cat .notary-profile)"
"""

from notarization_profile import resolve_profile

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args, capture=False):
    result = subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def paths(directory):
    directory = Path(directory).resolve()
    app = directory / "Glee.app"
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    version = info["CFBundleShortVersionString"]
    return directory, app, directory / f"Glee-{version}.dmg", info


def identity(preview=False):
    import os
    configured = os.environ.get("GLEE_SIGN_IDENTITY")
    if configured:
        return configured
    path = ROOT / ".signing-identity"
    if path.is_file():
        return path.read_text().strip()
    if preview:
        return "-"
    raise ValueError("Public DMGs require a configured Developer ID signing identity.")


def build(args):
    directory, app, dmg, info = paths(args.directory)
    if args.preview:
        dmg = dmg.with_stem(f"{dmg.stem}-preview")
    if dmg.exists():
        raise SystemExit(f"Refusing to overwrite {dmg}")
    run("codesign", "--verify", "--deep", "--strict", app)
    if not args.preview:
        run("xcrun", "stapler", "validate", app)
        run("spctl", "--assess", "--type", "execute", app)
    artwork = ROOT / ".build/dmg-artwork"
    run("swift", ROOT / "script/create_dmg_background.swift", artwork)

    # The generator embeds provenance and both resolutions in the TIFF itself.
    specification = {
        "title": "Glee.app Installer",
        "icon": str(app / "Contents/Resources/Glee.icns"),
        "background": str(artwork / "background.tiff"),
        "icon-size": 96,
        "window": {"position": {"x": 220, "y": 200},
                   "size": {"width": 520, "height": 260}},
        "format": "UDZO",
        "filesystem": "HFS+",
        "contents": [
            {"x": 130, "y": 112, "type": "file", "path": str(app)},
            {"x": 390, "y": 112, "type": "link", "path": "/Applications"},
        ],
    }
    spec = artwork / "appdmg.json"
    spec.write_text(json.dumps(specification, indent=2) + "\n")
    module = Path(args.appdmg_module).resolve()
    run("node", module / "bin/appdmg.js", spec, dmg)
    signing_identity = identity(preview=args.preview)
    signing = ["codesign", "--sign", signing_identity]
    if signing_identity != "-":
        signing.append("--timestamp")
    run(*signing, dmg)
    run("codesign", "--verify", "--strict", dmg)
    if args.preview:
        print(f"Created local preview {dmg}. This preview is not notarized for distribution.")
    else:
        print(f"Created {dmg}. Inspect the mounted Finder window before notarizing.")


def notarize(args):
    directory, app, dmg, info = paths(args.directory)
    run("codesign", "--verify", "--strict", dmg)
    result = json.loads(run("xcrun", "notarytool", "submit", dmg,
                            "--keychain-profile", resolve_profile(args.notary_profile),
                            "--wait", "--output-format", "json", capture=True))
    (directory / "dmg-notarization.json").write_text(json.dumps(result, indent=2) + "\n")
    if result.get("status") != "Accepted":
        raise SystemExit(f"DMG notarization did not pass: {result.get('status')}")
    run("xcrun", "stapler", "staple", dmg)
    run("xcrun", "stapler", "validate", dmg)
    run("codesign", "--verify", "--strict", dmg)
    run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", dmg)
    manifest = {
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "file": dmg.name,
        "sha256": hashlib.sha256(dmg.read_bytes()).hexdigest(),
        "notarization_id": result["id"],
    }
    (directory / "dmg-release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Ready to upload: {dmg}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("build")
    command.add_argument("directory")
    command.add_argument("--appdmg-module", default=ROOT / ".build/dmg-tools/node_modules/appdmg")
    command.add_argument("--preview", action="store_true",
                         help="Build a local preview DMG without requiring notarization; never use it as a release asset")
    command.set_defaults(function=build)
    command = commands.add_parser("notarize")
    command.add_argument("directory")
    command.add_argument("--notary-profile", required=True)
    command.set_defaults(function=notarize)
    args = parser.parse_args()
    args.function(args)
