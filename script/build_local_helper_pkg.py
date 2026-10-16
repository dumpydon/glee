#!/usr/bin/env python3
"""Build a per-Mac, per-binary Glee Local Helper administrator installer.

No Apple account, signing certificate, password, or private key is an input.
The already-signed app is read only. Apple's Installer requests administrator
approval when the generated unsigned local package is opened.

  python3 script/build_local_helper_pkg.py build --app dist/Glee.app \
      --output dist/Glee-Local-Helper.pkg
  python3 script/build_local_helper_pkg.py uninstall \
      --output dist/Glee-Local-Helper-Uninstall.pkg

Rebuild/reinstall the package when app/helper code changes. These packages are
for this Mac and owner UID, not public distribution or automatic updates.
"""

import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

APP_ID = "com.dumpydon.glee"
SERVICE = "com.dumpydon.glee.helper"
PACKAGE_ID = "com.dumpydon.glee.local-helper"
HELPER_PATH = Path("/Library/PrivilegedHelperTools") / SERVICE
DAEMON_PATH = Path("/Library/LaunchDaemons") / (SERVICE + ".plist")
CONFIG_DIRECTORY = Path("/Library/Application Support/Glee/LocalHelper")
MANIFEST_PATH = CONFIG_DIRECTORY / "identity.plist"
PENDING_MANIFEST_PATH = CONFIG_DIRECTORY / "identity.pending.plist"
RECOVERY_PATH = Path("/private/var/db") / SERVICE / "recovery.json"


def run(arguments, *, timeout=60):
    return subprocess.run([str(item) for item in arguments], check=True,
                          capture_output=True, text=True, timeout=timeout)


def validate_owner_uid(value=None):
    value = os.getuid() if value is None else value
    if isinstance(value, bool):
        raise ValueError("The local helper owner UID must be a positive nonroot integer.")
    text = str(value)
    if not re.fullmatch(r"[0-9]+", text) or not 0 < int(text) < 2**32 - 1:
        raise ValueError("The local helper owner UID must be a positive nonroot integer; use --owner-uid when building as root.")
    return int(text)


def require_regular_file(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise ValueError("Expected an ordinary file, not a missing file or symlink: " + str(path))
    return path


def app_files(app):
    requested = Path(app).expanduser()
    if requested.is_symlink():
        raise ValueError("Use the actual Glee.app path rather than an app symlink.")
    bundle = requested.resolve(strict=True)
    if not bundle.is_dir() or bundle.suffix.lower() != ".app":
        raise ValueError("--app must name a built Glee.app bundle.")
    # Do not traverse mutable in-bundle aliases to pin an unrelated executable.
    for relative in ("Contents", "Contents/MacOS", "Contents/Library", "Contents/Library/HelperTools"):
        directory = bundle / relative
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError("The app has a missing or symlinked bundle directory: " + str(directory))
    info_path = require_regular_file(bundle / "Contents/Info.plist")
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    if (not isinstance(info, dict) or info.get("CFBundleIdentifier") != APP_ID
            or info.get("CFBundleExecutable") != "Glee"):
        raise ValueError("The app must have the Glee bundle identifier and executable.")
    executable = require_regular_file(bundle / "Contents/MacOS/Glee")
    helper = require_regular_file(bundle / "Contents/Library/HelperTools/GleeHelper")
    return bundle, executable, helper


def code_hashes(executable, identifier):
    """Read exact CDHashes for every architecture; do not assume host arch."""
    arch_text = run(["/usr/bin/lipo", "-archs", executable]).stdout.strip()
    architectures = arch_text.split()
    if (not architectures or len(set(architectures)) != len(architectures)
            or any(not re.fullmatch(r"[a-z][a-z0-9_]{0,23}", arch) for arch in architectures)):
        raise ValueError("lipo did not report an unambiguous executable architecture list.")
    hashes = []
    for arch in architectures:
        result = run(["/usr/bin/codesign", "-d", "--verbose=4", "--arch", arch, executable])
        display = result.stdout + "\n" + result.stderr
        identifiers = re.findall(r"^Identifier=(.+)$", display, flags=re.MULTILINE)
        values = re.findall(r"^CDHash=([0-9a-fA-F]{40})$", display, flags=re.MULTILINE)
        if identifiers != [identifier] or len(values) != 1:
            raise ValueError("codesign did not report the expected identifier and one 40-hex CDHash for " + arch)
        value = values[0].lower()
        if value not in hashes:
            hashes.append(value)
    return hashes


def identity_manifest(owner_uid, app_hashes, helper_hashes):
    owner_uid = validate_owner_uid(owner_uid)
    for label, values in (("app", app_hashes), ("helper", helper_hashes)):
        if (not isinstance(values, list) or not 1 <= len(values) <= 4
                or any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{40}", value) for value in values)
                or len(values) != len(set(values))):
            raise ValueError(label + "CodeHashes must be a nonempty list of unique lowercase 40-hex hashes.")
    return {"formatVersion": 1, "ownerUID": owner_uid,
            "appCodeHashes": app_hashes, "helperCodeHashes": helper_hashes}


def daemon_configuration():
    return {"Label": SERVICE, "ProgramArguments": [str(HELPER_PATH)],
            "MachServices": {SERVICE: True}, "UserName": "root",
            "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 5,
            "Umask": 0o077}


# Fixed absolute paths only. No user-supplied text is interpolated into root scripts.
# `ioreg` renders a CFBoolean as No/Yes. A missing/string/number/multiple reading
# never passes this exact check; pmset's omitted preference is not treated as false.
ACL_CHECK_PROGRAM = r'''
    /^[[:space:]]*[0-9]+:/ {
        if ($0 ~ /[[:space:]]deny[[:space:]]/) next
        if ($0 !~ /[[:space:]]allow[[:space:]]/) exit 1
        rights = $0
        sub(/^.*[[:space:]]allow[[:space:]]+/, "", rights)
        count = split(rights, permissions, /[[:space:],]+/)
        for (permission_index = 1; permission_index <= count; permission_index++) {
            # Only known nonmutating rights and inheritance flags pass. This
            # rejects write/delete/chown/security/attribute rights, and fails
            # closed for unknown future permission vocabulary.
            if (permissions[permission_index] !~ /^(read|readattr|readextattr|readsecurity|list|search|execute|file_inherit|directory_inherit|limit_inherit|only_inherit|inherited)$/) exit 1
        }
    }
'''

SCRIPT_GUARDS = r'''#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

SERVICE='com.dumpydon.glee.helper'
HELPER='/Library/PrivilegedHelperTools/com.dumpydon.glee.helper'
DAEMON='/Library/LaunchDaemons/com.dumpydon.glee.helper.plist'
CONFIG_DIR='/Library/Application Support/Glee/LocalHelper'
MANIFEST="$CONFIG_DIR/identity.plist"
PENDING="$CONFIG_DIR/identity.pending.plist"
JOURNAL='/private/var/db/com.dumpydon.glee.helper/recovery.json'

fail() { /bin/echo "Glee Local Helper: $*" >&2; exit 1; }

[[ "$(/usr/bin/id -u)" == 0 ]] || fail 'Run this package using macOS Installer administrator approval.'
[[ "${3:-/}" == '/' ]] || fail 'This local package can only be installed on the current startup volume.'

check_acl() {
    local item="$1" acl
    acl=$(/bin/ls -lde "$item") || fail "Could not verify ACL permissions: $item"
    if ! /usr/bin/awk '__ACL_CHECK_PROGRAM__' <<< "$acl"; then
        fail "ACL grants mutation or unknown permissions on protected path: $item"
    fi
}

check_directory() {
    local item="$1"
    [[ ! -L "$item" ]] || fail "Refusing symlinked installation directory: $item"
    if [[ -e "$item" ]]; then
        [[ -d "$item" ]] || fail "Expected a directory: $item"
        [[ "$(/usr/bin/stat -f '%u' "$item")" == 0 ]] || fail "Directory must be root-owned: $item"
        local permissions
        permissions=$(/usr/bin/stat -f '%Lp' "$item")
        (( (8#$permissions & 0022) == 0 )) || fail "Directory must not be writable by other users: $item"
        check_acl "$item"
    fi
}

check_file() {
    local item="$1"
    [[ ! -L "$item" ]] || fail "Refusing symlinked installation file: $item"
    if [[ -e "$item" ]]; then
        [[ -f "$item" ]] || fail "Expected a regular file: $item"
        [[ "$(/usr/bin/stat -f '%u:%l' "$item")" == '0:1' ]] || fail "File must be root-owned with one link: $item"
        local permissions
        permissions=$(/usr/bin/stat -f '%Lp' "$item")
        (( (8#$permissions & 0022) == 0 )) || fail "File must not be writable by other users: $item"
        check_acl "$item"
    fi
}

require_safe_state() {
    local item
    for item in '/Library' '/Library/Application Support' '/Library/Application Support/Glee' "$CONFIG_DIR" '/Library/PrivilegedHelperTools' '/Library/LaunchDaemons' '/private/var/db' '/private/var/db/com.dumpydon.glee.helper'; do
        check_directory "$item"
    done
    for item in "$HELPER" "$DAEMON" "$MANIFEST" "$PENDING"; do check_file "$item"; done
    [[ ! -e "$JOURNAL" && ! -L "$JOURNAL" ]] || fail 'Sleep recovery is pending. Keep the lid open, end your Glee session, and wait for normal sleep to be restored before trying again.'

    local registry state
    registry=$(/usr/sbin/ioreg -r -n IOPMrootDomain -d 1) || fail 'Could not read the kernel sleep setting.'
    state=$(/usr/bin/awk '
        /^[[:space:]]*"SleepDisabled"[[:space:]]*=/ {
            count++
            if ($0 ~ /^[[:space:]]*"SleepDisabled"[[:space:]]*=[[:space:]]*No[[:space:]]*$/) safe++
        }
        END { if (count == 1 && safe == 1) print "normal"; else print "unknown-or-disabled" }
    ' <<< "$registry")
    [[ "$state" == 'normal' ]] || fail 'macOS has not definitely restored normal sleep. Keep the lid open and end existing closed-lid sessions first.'

    local other status path
    for other in 'app.wakebee.helper' 'com.awakemac.helper'; do
        for path in "/Library/LaunchDaemons/$other.plist" "/Library/PrivilegedHelperTools/$other" "/private/var/db/$other/recovery.json"; do
            [[ ! -e "$path" && ! -L "$path" ]] || fail 'Another sleep app has a helper/recovery still installed. Remove its closed-lid setup using that app before installing Glee. The other app was not changed.'
        done
        if /bin/launchctl print "system/$other" >/dev/null 2>&1; then
            fail 'Another sleep app has a helper still registered. Remove its closed-lid setup using that app first. The other app was not changed.'
        else
            status=$?
            [[ "$status" == 113 ]] || fail 'Could not safely check the existing sleep helper. No service was removed.'
        fi
    done
}

stop_local_service() {
    local status description loaded_path
    if description=$(/bin/launchctl print "system/$SERVICE" 2>/dev/null); then
        [[ -f "$DAEMON" && ! -L "$DAEMON" ]] || fail 'Glee has a signed-app helper registered. Remove that setup from Glee settings before using the local installer.'
        loaded_path=$(/usr/bin/awk '
            /^[[:space:]]*path[[:space:]]*=/ {
                count++
                if ($0 ~ /^[[:space:]]*path[[:space:]]*=[[:space:]]*\/Library\/LaunchDaemons\/com\.dumpydon\.glee\.helper\.plist[[:space:]]*$/) local_path++
            }
            END { if (count == 1 && local_path == 1) print "local"; else print "other-or-unknown" }
        ' <<< "$description")
        [[ "$loaded_path" == 'local' ]] || fail 'The registered Glee service is not this local installer’s daemon. Remove its setup from Glee settings first. No service was removed.'
        /bin/launchctl bootout "system/$SERVICE" || fail 'Could not stop the existing local Glee helper. No replacement will be started.'
    else
        status=$?
        [[ "$status" == 113 ]] || fail 'Could not safely inspect the Glee helper. No service was removed.'
    fi
}
'''.replace("__ACL_CHECK_PROGRAM__", ACL_CHECK_PROGRAM)


def installer_scripts(uninstall=False):
    preinstall = SCRIPT_GUARDS + "\nrequire_safe_state\nstop_local_service\nrequire_safe_state\n"
    if uninstall:
        postinstall = SCRIPT_GUARDS + r'''
require_safe_state
# Remove only this local installation's exact files. Never delete a recovery
# journal or another product's helper. rmdir preserves any nonempty directory.
/bin/rm -f "$DAEMON" "$HELPER" "$MANIFEST" "$PENDING"
/bin/rmdir "$CONFIG_DIR" 2>/dev/null || true
/bin/rmdir '/Library/Application Support/Glee' 2>/dev/null || true
/bin/echo 'Glee Local Helper removed. Normal sleep remains enabled.'
'''
    else:
        postinstall = SCRIPT_GUARDS + r'''
require_safe_state
# Resource files live in the package's Installer-owned script extraction area.
# No Payload/BOM entries rewrite shared /Library directory metadata.
SCRIPT_DIR="$(cd -- "$(/usr/bin/dirname "$0")" && pwd -P)"
RESOURCE_DIR="$SCRIPT_DIR/resources"
[[ -d "$RESOURCE_DIR" && ! -L "$RESOURCE_DIR" ]] || fail 'The local helper package resources are incomplete.'
for item in "$RESOURCE_DIR/GleeHelper" "$RESOURCE_DIR/daemon.plist" "$RESOURCE_DIR/identity.pending.plist"; do
    # Script resources retain the package author's UID in pkgbuild's archive;
    # they are approved package inputs, not installed root trust-policy files.
    [[ -f "$item" && ! -L "$item" && "$(/usr/bin/stat -f '%l' "$item")" == 1 ]] || fail 'The local helper package resources are incomplete or aliased.'
done

# Only create a shared parent if absent; never chmod/chown/strip its existing ACL.
for item in '/Library/PrivilegedHelperTools' '/Library/LaunchDaemons'; do
    if [[ ! -d "$item" ]]; then /usr/bin/install -d -o root -g wheel -m 0755 "$item"; fi
done
/usr/bin/install -d -o root -g wheel -m 0755 '/Library/Application Support/Glee' "$CONFIG_DIR"
/bin/chmod -N '/Library/Application Support/Glee' "$CONFIG_DIR"
/bin/chmod 0755 '/Library/Application Support/Glee' "$CONFIG_DIR"
require_safe_state

HELPER_TEMP=''
DAEMON_TEMP=''
MANIFEST_TEMP=''
cleanup() {
    # These are only root-created exclusive temporary files in protected dirs.
    [[ -z "$HELPER_TEMP" ]] || /bin/rm -f "$HELPER_TEMP"
    [[ -z "$DAEMON_TEMP" ]] || /bin/rm -f "$DAEMON_TEMP"
    [[ -z "$MANIFEST_TEMP" ]] || /bin/rm -f "$MANIFEST_TEMP"
}
trap cleanup EXIT
HELPER_TEMP=$(/usr/bin/mktemp '/Library/PrivilegedHelperTools/.com.dumpydon.glee.helper.XXXXXX')
DAEMON_TEMP=$(/usr/bin/mktemp '/Library/LaunchDaemons/.com.dumpydon.glee.helper.XXXXXX')
MANIFEST_TEMP=$(/usr/bin/mktemp "$CONFIG_DIR/.identity.XXXXXX")
/usr/bin/install -o root -g wheel -m 0755 "$RESOURCE_DIR/GleeHelper" "$HELPER_TEMP"
/usr/bin/install -o root -g wheel -m 0644 "$RESOURCE_DIR/daemon.plist" "$DAEMON_TEMP"
/usr/bin/install -o root -g wheel -m 0644 "$RESOURCE_DIR/identity.pending.plist" "$MANIFEST_TEMP"
/bin/chmod -N "$HELPER_TEMP" "$DAEMON_TEMP" "$MANIFEST_TEMP"
/bin/chmod 0755 "$HELPER_TEMP"
/bin/chmod 0644 "$DAEMON_TEMP" "$MANIFEST_TEMP"
check_file "$HELPER_TEMP"
check_file "$DAEMON_TEMP"
check_file "$MANIFEST_TEMP"
/usr/bin/codesign --verify --strict "$HELPER_TEMP" || fail 'The staged helper signature could not be verified.'
/usr/bin/plutil -lint "$DAEMON_TEMP" "$MANIFEST_TEMP" || fail 'The staged helper policy or daemon plist is malformed.'
require_safe_state
/bin/mv -f "$HELPER_TEMP" "$HELPER"
HELPER_TEMP=''
/bin/mv -f "$DAEMON_TEMP" "$DAEMON"
DAEMON_TEMP=''
/bin/mv -f "$MANIFEST_TEMP" "$PENDING"
MANIFEST_TEMP=''
# Publish the root-owned identity atomically only after helper/plist permissions
# are secured. Never launch the daemon against a half-installed identity.
/bin/mv -f "$PENDING" "$MANIFEST"
require_safe_state
/bin/launchctl bootstrap system "$DAEMON" || fail 'The helper could not start. Keep the lid open and retry setup.'
/bin/launchctl enable "system/$SERVICE"
/bin/launchctl kickstart "system/$SERVICE"
/bin/echo 'Glee Local Helper installed for this app build. Return to Glee and wait for Ready before closing the lid.'
'''
    return {"preinstall": preinstall, "postinstall": postinstall}


def write_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        plistlib.dump(value, handle, fmt=plistlib.FMT_XML, sort_keys=True)
    path.chmod(0o644)


def output_path(path, bundle=None):
    requested = Path(path).expanduser()
    if requested.suffix.lower() != ".pkg":
        raise ValueError("The output must be a new .pkg file.")
    output = requested.absolute()
    output = output.parent.resolve(strict=False) / output.name
    if bundle is not None and (output == bundle or bundle in output.parents):
        raise ValueError("The package must be written outside the read-only app bundle.")
    if output.exists() or output.is_symlink():
        raise FileExistsError("Refusing to overwrite existing package: " + str(output))
    output.parent.mkdir(parents=True, exist_ok=True)
    return output


def build_package(*, output, app=None, owner_uid=None, uninstall=False):
    if uninstall:
        if app is not None or owner_uid is not None:
            raise ValueError("The uninstall package takes no app or owner UID.")
        bundle = executable = helper = None
    else:
        if app is None:
            raise ValueError("Supply --app with the built Glee.app path.")
        owner_uid = validate_owner_uid(owner_uid)
        bundle, executable, helper = app_files(app)
    output = output_path(output, bundle=bundle)
    with tempfile.TemporaryDirectory(prefix=".glee-local-helper-", dir=str(output.parent)) as temporary:
        staging = Path(temporary)
        scripts = staging / "scripts"
        scripts.mkdir()
        for name, contents in installer_scripts(uninstall).items():
            script = scripts / name
            script.write_text(contents, encoding="utf-8")
            script.chmod(0o755)
        command = ["/usr/bin/pkgbuild", "--identifier", PACKAGE_ID + (".uninstall" if uninstall else ""),
                   "--version", "1", "--install-location", "/", "--scripts", scripts]
        # Installer script resources avoid a root payload BOM that would
        # overwrite ownership/modes/ACLs of existing shared parent directories.
        command.append("--nopayload")
        if not uninstall:
            run(["/usr/bin/codesign", "--verify", "--deep", "--strict", bundle])
            run(["/usr/bin/codesign", "--verify", "--strict", helper])
            resources = scripts / "resources"
            resources.mkdir()
            staged_helper = resources / "GleeHelper"
            shutil.copyfile(helper, staged_helper)
            staged_helper.chmod(0o755)
            run(["/usr/bin/codesign", "--verify", "--strict", staged_helper])
            app_hashes = code_hashes(executable, APP_ID)
            helper_hashes = code_hashes(staged_helper, SERVICE)
            # Recheck source identities after collection so a concurrent rebuild
            # cannot silently generate a manifest for two different app builds.
            run(["/usr/bin/codesign", "--verify", "--deep", "--strict", bundle])
            if code_hashes(executable, APP_ID) != app_hashes or code_hashes(helper, SERVICE) != helper_hashes:
                raise ValueError("The app changed while its local installer was being prepared. Quit/rebuild, then retry.")
            write_plist(resources / "identity.pending.plist",
                        identity_manifest(owner_uid, app_hashes, helper_hashes))
            write_plist(resources / "daemon.plist", daemon_configuration())
        staged_package = staging / ("Glee-Local-Helper-Uninstall.pkg" if uninstall else "Glee-Local-Helper.pkg")
        command.append(staged_package)
        run(command)
        require_regular_file(staged_package)
        staged_package.chmod(0o644)
        # Same-filesystem hard-link publication is atomic and refuses an existing
        # output even if another process creates it during pkgbuild. No overwrite.
        os.link(staged_package, output)
    return output


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    install = commands.add_parser("build", help="Build Glee Local Helper installer for an existing signed app")
    install.add_argument("app_path", nargs="?", help="Built Glee.app path (alternative to --app)")
    install.add_argument("--app", help="Built Glee.app path; the app is never modified")
    install.add_argument("--owner-uid", help="Nonroot UID to authorize; defaults to current invoker UID")
    install.add_argument("--output", required=True, help="New output .pkg path; existing files are never overwritten")
    remove = commands.add_parser("uninstall", help="Build Glee Local Helper removal package")
    remove.add_argument("--output", required=True, help="New output .pkg path")
    args = parser.parse_args(argv)
    if args.command == "build" and (bool(args.app) == bool(args.app_path)):
        parser.error("Supply the app exactly once using --app or the positional app path.")
    try:
        result = build_package(output=args.output,
                               app=(args.app or args.app_path) if args.command == "build" else None,
                               owner_uid=args.owner_uid if args.command == "build" else None,
                               uninstall=args.command == "uninstall")
    except (ValueError, OSError, plistlib.InvalidFileException, subprocess.SubprocessError) as error:
        print("Glee Local Helper package was not created: " + str(error), file=sys.stderr)
        return 1
    print(result)
    print("Open this local package in macOS Installer and approve it there. Recreate it after rebuilding Glee.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
