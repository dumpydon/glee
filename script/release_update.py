#!/usr/bin/env python3
"""Prepare notarized Sparkle updates; publish only with an explicit subcommand."""
from notarization_profile import resolve_profile

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "dumpydon/glee"
# The same signing key is retained under its Glee account name.
ACCOUNT = os.environ.get("GLEE_UPDATE_KEY_ACCOUNT", "com.dumpydon.glee.updates")
TOOLS = ROOT / ".build/artifacts/sparkle/Sparkle/bin"
FEED_API = f"repos/{REPOSITORY}/contents/appcast.xml"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def run(*args, capture=False, **kwargs):
    result = subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None, **kwargs)
    return result.stdout.strip() if capture else None


def configuration():
    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("Use a three-part version and a positive integer build number in Resources/Info.plist.")
    return info


def current_feed():
    response = json.loads(run("gh", "api", FEED_API, capture=True))
    return response["sha"], base64.b64decode(response["content"])


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_bundle(app):
    run("codesign", "--verify", "--deep", "--strict", app)
    signature = subprocess.run(["codesign", "-dvv", str(app)], check=True,
                               capture_output=True, text=True).stderr
    if "Authority=Developer ID Application:" not in signature:
        raise ValueError("Public updates require a Developer ID Application signature.")


def prepare(args):
    info = configuration()
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    tag = f"v{version}"
    notes = ROOT / "Updates" / f"{version}.html"
    if not notes.is_file():
        raise ValueError(f"Write release notes in {notes} before preparing this release.")
    output = ROOT / "dist/updates" / f"{version}-{build}"
    output.mkdir(parents=True, exist_ok=False)
    app = output / "Glee.app"
    env = dict(os.environ, GLEE_BUILD_CONFIGURATION="release", GLEE_UNIVERSAL="1",
               GLEE_DESTINATION=str(app))
    run(ROOT / "script/build_and_run.sh", "--build-only", env=env)
    verify_bundle(app)
    for binary in [app / "Contents/MacOS/Glee", app / "Contents/Library/HelperTools/GleeHelper"]:
        for architecture in ("arm64", "x86_64"):
            run("xcrun", "lipo", binary, "-verify_arch", architecture)

    public_key = run(TOOLS / "generate_keys", "--account", ACCOUNT, "-p", capture=True)
    if public_key != info["SUPublicEDKey"]:
        raise ValueError("The Keychain signing key does not match Glee's embedded public key.")
    old_sha, old_feed = current_feed()
    appcast = output / "appcast.xml"
    appcast.write_bytes(old_feed)
    run(TOOLS / "sign_update", "--account", ACCOUNT, "--verify", appcast)
    old_builds = [int(item.text) for item in ET.fromstring(old_feed).iter(f"{SPARKLE}version")]
    if old_builds and int(build) <= max(old_builds):
        raise ValueError("CFBundleVersion must be higher than every already-published build.")

    # Only the app bundle enters the archive. Credentials and source stay local.
    submission = output / "notarization.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, submission)
    response = json.loads(run("xcrun", "notarytool", "submit", submission,
                              "--keychain-profile", resolve_profile(args.notary_profile), "--wait",
                              "--output-format", "json", capture=True))
    (output / "notarization.json").write_text(json.dumps(response, indent=2) + "\n")
    if response.get("status") != "Accepted":
        raise ValueError(f"Notarization was not accepted. See {output / 'notarization.json'}")
    run("xcrun", "stapler", "staple", app)
    run("xcrun", "stapler", "validate", app)
    run("spctl", "--assess", "--type", "execute", app)
    submission.unlink()

    archive = output / f"Glee-{version}.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
    (output / f"Glee-{version}.html").write_bytes(notes.read_bytes())
    run(TOOLS / "generate_appcast", "--account", ACCOUNT, "--maximum-deltas", "0",
        "--download-url-prefix", f"https://github.com/{REPOSITORY}/releases/download/{tag}/",
        "--link", "https://github.com/dumpydon/glee", "--embed-release-notes", output)
    run(TOOLS / "sign_update", "--account", ACCOUNT, "--verify", appcast)
    manifest = {"version": version, "build": build, "tag": tag, "previous_feed_sha": old_sha,
                "archive": archive.name, "archive_sha256": digest(archive),
                "feed_sha256": digest(appcast), "public_key": public_key}
    (output / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared and verified: {output}\nReview, then publish: python3 script/release_update.py publish '{output}'")


def publish(args):
    output = args.directory.resolve()
    manifest = json.loads((output / "release.json").read_text())
    info = configuration()
    version, tag = manifest["version"], manifest["tag"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or tag != f"v{version}":
        raise ValueError("Invalid release version/tag.")
    if manifest["archive"] != f"Glee-{version}.zip":
        raise ValueError("Invalid archive name.")
    archive, appcast = output / manifest["archive"], output / "appcast.xml"
    if digest(archive) != manifest["archive_sha256"] or digest(appcast) != manifest["feed_sha256"]:
        raise ValueError("Prepared release changed. Prepare it again before publishing.")
    if manifest["public_key"] != info["SUPublicEDKey"]:
        raise ValueError("Prepared release does not match the configured signing key.")
    run(TOOLS / "sign_update", "--account", ACCOUNT, "--verify", appcast)
    run("xcrun", "stapler", "validate", output / "Glee.app")
    old_sha, _ = current_feed()
    if old_sha != manifest["previous_feed_sha"]:
        raise ValueError("The public feed changed. Prepare against its latest version before publishing.")

    notes = args.notes_file.resolve() if getattr(args, "notes_file", None) else ROOT / "Updates" / f"{version}.html"
    if not notes.is_file():
        raise ValueError(f"Release notes were not found: {notes}")
    # Fail if the tag exists; never overwrite release assets users may be downloading.
    run("gh", "release", "create", tag, archive, "--repo", REPOSITORY, "--draft",
        "--title", f"Glee {version}", "--notes-file", notes)
    prerelease = getattr(args, "prerelease", False)
    run("gh", "release", "edit", tag, "--repo", REPOSITORY, "--draft=false",
        "--prerelease" if prerelease else "--prerelease=false",
        "--latest=false" if prerelease else "--latest")
    # Publish the binary before the feed, and use SHA-based concurrency control.
    payload = {"message": f"Publish Glee {version} update feed", "sha": old_sha,
               "content": base64.b64encode(appcast.read_bytes()).decode(), "branch": "main"}
    run("gh", "api", "--method", "PUT", FEED_API, "--input", "-",
        input=json.dumps(payload), capture=True)
    print(f"Published https://github.com/{REPOSITORY}/releases/tag/{tag}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare", help="Build, notarize, and sign an update locally")
    prepare_parser.add_argument("--notary-profile", required=True,
                                help="Existing notarytool Keychain profile name; never a password")
    prepare_parser.set_defaults(action=prepare)
    publish_parser = commands.add_parser("publish", help="Publish a reviewed, notarized update to GitHub")
    publish_parser.add_argument("directory", type=Path)
    publish_parser.add_argument("--prerelease", action="store_true", help="Mark a friends/testers release as a GitHub prerelease")
    publish_parser.add_argument("--notes-file", type=Path, help="Optional public Markdown installation and testing notes")
    publish_parser.set_defaults(action=publish)
    args = parser.parse_args()
    try:
        args.action(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
