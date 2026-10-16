#!/usr/bin/env python3
"""Create and inspect a local Glee installer preview without Finder automation.

Install isolated tooling once (Python 3.10+):
  python3 -m venv .build/dmg-tools
  .build/dmg-tools/bin/python3 -m pip install dmgbuild==1.6.7

Build the already-signed app; --keep-mounted leaves a read-only visual preview:
  .build/dmg-tools/bin/python3 script/build_local_dmg.py --keep-mounted

This is a local, unsigned, unnotarized DMG. It neither modifies the app nor
installs a privileged helper. Existing output files are never replaced.
"""

import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DMGBUILD_VERSION = "1.6.7"


def run(arguments, timeout=180):
    try:
        return subprocess.run([str(value) for value in arguments], check=True,
                              capture_output=True, timeout=timeout)
    except subprocess.CalledProcessError as error:
        details = (error.stderr or error.stdout or b"").decode("utf-8", errors="replace")[-8192:]
        raise ValueError("Command failed: " + str(arguments[0]) + "\n" + details) from error


def snapshot(directory):
    """Hash file bytes and symlink targets, without following app aliases."""
    records = {}
    for path in sorted(directory.rglob("*")):
        relative = str(path.relative_to(directory))
        if path.is_symlink():
            records[relative] = {"symlink": os.readlink(path)}
        elif path.is_file():
            records[relative] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        elif path.is_dir():
            records[relative] = {"directory": True}
        else:
            raise ValueError("Unexpected nonordinary app resource: " + str(path))
    return records


def finder_settings(app, background):
    return {"format": "UDZO", "filesystem": "HFS+",
            "files": [(str(app), "Glee.app")],
            "symlinks": {"Applications": "/Applications"},
            "icon": str(app / "Contents/Resources/Glee.icns"),
            "background": str(background), "default_view": "icon-view",
            "window_rect": ((220, 200), (520, 260)),
            "icon_locations": {"Glee.app": (130, 112), "Applications": (390, 112)},
            "icon_size": 96, "text_size": 12, "grid_spacing": 80,
            "arrange_by": None, "label_pos": "bottom",
            "show_toolbar": False, "show_status_bar": False,
            "show_tab_view": False, "show_pathbar": False, "show_sidebar": False}


def inspect_image(image, app_snapshot, keep_mounted=False):
    from ds_store import DSStore
    attached = plistlib.loads(run(["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-plist", image]).stdout)
    mounted = [entry for entry in attached["system-entities"] if entry.get("mount-point")]
    if len(mounted) != 1:
        for entry in mounted:
            run(["/usr/bin/hdiutil", "detach", entry["dev-entry"]])
        raise ValueError("Expected one mounted installer volume.")
    entity = mounted[0]
    volume = Path(entity["mount-point"])
    success = False
    try:
        if snapshot(volume / "Glee.app") != app_snapshot:
            raise ValueError("The DMG's app bytes or symlink targets differ from the source bundle.")
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", volume / "Glee.app"])
        if not (volume / "Applications").is_symlink() or os.readlink(volume / "Applications") != "/Applications":
            raise ValueError("The installer Applications link is invalid.")
        with DSStore.open(str(volume / ".DS_Store"), "r") as store:
            window = store["."]["bwsp"]
            icons = store["."]["icvp"]
            positions = {name: store[name]["Iloc"] for name in ("Glee.app", "Applications")}
        if window["WindowBounds"] != "{{220, 200}, {520, 260}}":
            raise ValueError("The installer window does not match the original 520×260 layout.")
        if icons["iconSize"] != 96 or icons["backgroundType"] != 2:
            raise ValueError("The installer icon size or custom background metadata is missing.")
        if positions != {"Glee.app": (130, 112), "Applications": (390, 112)}:
            raise ValueError("The installer icon locations do not match the original layout.")
        report = {"mountPoint": str(volume), "device": entity["dev-entry"],
                  "readOnly": True, "appBytesUnchanged": True, "appSignatureVerified": True,
                  "inventory": sorted(item.name for item in volume.iterdir()),
                  "window": window, "iconSize": icons["iconSize"], "textSize": icons["textSize"],
                  "iconLocations": positions,
                  "backgroundSHA256": hashlib.sha256((volume / ".background.tiff").read_bytes()).hexdigest()}
        success = True
        return report
    finally:
        if not success or not keep_mounted:
            run(["/usr/bin/hdiutil", "detach", entity["dev-entry"]])


def build(app, output, keep_mounted=False):
    import dmgbuild
    if importlib.metadata.version("dmgbuild") != DMGBUILD_VERSION:
        raise ValueError("Use the isolated dmgbuild==" + DMGBUILD_VERSION + " environment.")
    app = Path(app).expanduser().resolve(strict=True)
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("Supply a built Glee.app bundle.")
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleIdentifier") != "com.dumpydon.glee" or info.get("CFBundleExecutable") != "Glee":
        raise ValueError("This installer only packages Glee.")
    output = Path(output).expanduser().absolute()
    output = output.parent.resolve(strict=False) / output.name
    if output.suffix != ".dmg" or app in output.parents:
        raise ValueError("The output must be a new .dmg outside the read-only app.")
    if output.exists() or output.is_symlink():
        raise FileExistsError("Refusing to replace " + str(output))
    output.parent.mkdir(parents=True, exist_ok=True)
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    original = snapshot(app)
    with tempfile.TemporaryDirectory(prefix=".glee-local-dmg-", dir=str(output.parent)) as temporary:
        staging = Path(temporary)
        art = staging / "artwork"
        # A fixed shell program sources the project's existing Swift 6 selector;
        # paths are separate argv values, never interpolated shell code.
        run(["/bin/bash", "-c", 'set -euo pipefail; source "$1"; "$SWIFT_EXEC" "$2" -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers -o "$3"; "$3" "$4"',
             "glee-dmg-artwork", ROOT / "script/swift_environment.sh",
             ROOT / "script/create_dmg_background.swift", staging / "create-dmg-background", art])
        staged_image = staging / "Glee-2.0.0-local.dmg"
        dmgbuild.build_dmg(str(staged_image), "Glee.app Installer",
                           settings=finder_settings(app, art / "background.tiff"),
                           lookForHiDPI=False)
        if snapshot(app) != original:
            raise ValueError("The source app changed during packaging. No DMG was published.")
        run(["/usr/bin/hdiutil", "verify", staged_image])
        # Atomic same-filesystem publication fails if output appeared meanwhile.
        os.link(staged_image, output)
    verification = inspect_image(output, original, keep_mounted=keep_mounted)
    report = {"path": str(output), "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
              "bytes": output.stat().st_size, "localPreview": True, "notarized": False,
              "signed": False, "appVersion": info["CFBundleShortVersionString"],
              "dependencies": {name: importlib.metadata.version(name) for name in ("dmgbuild", "ds_store", "mac_alias")},
              "sourceAppTreeSHA256": hashlib.sha256(json.dumps(original, sort_keys=True).encode()).hexdigest(),
              "inspection": verification}
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", default=ROOT / "dist/Glee.app")
    parser.add_argument("--output", default=ROOT / "dist/Glee-2.0.0-local.dmg")
    parser.add_argument("--keep-mounted", action="store_true", help="Keep the verified read-only volume mounted for visual inspection")
    args = parser.parse_args(argv)
    try:
        report = build(args.app, args.output, args.keep_mounted)
    except (OSError, ValueError, ImportError, subprocess.SubprocessError) as error:
        print("Local DMG build failed: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
