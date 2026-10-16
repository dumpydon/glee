# Developing Glee

Glee uses an AppKit menu bar item and popover, SwiftUI controls, a policy/session core, and a bounded privileged XPC helper. Sessions are free and require no account or activation service.

## Build and run

Use macOS 14+, Swift 6, a macOS SDK, and Python 3. Xcode with SDK 26.1+ enables Liquid Glass; older SDKs compile the macOS 14/15 fallback controls.

```sh
./script/build_and_run.sh --build-only
open dist/Glee.app
```

Run the bundled app rather than the raw executable. The script finds Swift 6 on PATH or in `~/Library/Developer/Toolchains`. It does not change global Xcode selection or shell profiles.

| Variable | Purpose |
| --- | --- |
| `GLEE_SWIFT_EXEC` | Choose an absolute Swift executable. |
| `GLEE_BUILD_CONFIGURATION` | `debug` (default) or `release`. |
| `GLEE_UNIVERSAL=1` | Build Apple silicon and Intel slices with a suitable Xcode setup. |
| `GLEE_DESTINATION` | Choose an app output path; running destinations are protected. |
| `GLEE_SIGN_IDENTITY` | Apple certificate name/fingerprint; `-` uses local ad-hoc signing. |
| `GLEE_REGENERATE_ICON=1` | Regenerate ICNS from the Glee PNG. |

Both app and helper use hardened runtime signing. Local builds retain library validation and omit Sparkle. Build output, credentials, signing identities, and private notary material must stay out of Git.

## Local closed-lid setup

Choose **Set up…** in Glee. It prepares a package for the current Mac and opens macOS Installer. The administrator approves it using the Mac's dialog; Glee does not request or store the password.

The no-payload installer writes only fixed Glee paths after checking normal sleep, recovery state, permissions, and other sleep utilities. It preserves shared directory permissions.

| Path | Purpose |
| --- | --- |
| `/Library/PrivilegedHelperTools/com.dumpydon.glee.helper` | Root-owned helper. |
| `/Library/LaunchDaemons/com.dumpydon.glee.helper.plist` | Root daemon declaration. |
| `/Library/Application Support/Glee/LocalHelper/identity.plist` | Approved owner UID and exact app/helper code hashes. |
| `/private/var/db/com.dumpydon.glee.helper/recovery.json` | Recovery journal while restoration is needed. |

A rebuild requires renewed setup. Moving an unchanged app does not change its code hash. Use **Settings → Closed Lid → Advanced** to remove setup; removal refuses unresolved recovery state.

To prepare packages explicitly:

```sh
python3 script/build_local_helper_pkg.py build --app dist/Glee.app --output dist/Glee-Local-Helper.pkg
python3 script/build_local_helper_pkg.py uninstall --output dist/Glee-Local-Helper-Uninstall.pkg
```

Output paths must be new. Helper packages are generated on the receiving Mac, not shared between users.

## Checks

```sh
./script/check.sh
```

The script runs Swift Testing and Python unittest. Policy tests use simulated privileged settings; they do not install helpers or change real sleep settings.

For runtime checks, launch the actual app. Verify session modes, extensions, display controls, settings, and assertion release on End/Quit. For closed-lid changes, separately verify authenticated helper readiness, sleep-setting restoration, disconnect/recovery behavior, and a short physical lid test. See [verification](VERIFICATION.md).

The helper uses expiring leases, a four-hour continuous limit, battery and thermal cutoffs, and a durable prior-setting journal. Do not weaken these rules or the checks that prevent another utility's helper from overlapping Glee.

## Package a DMG

Use an isolated Python 3.10+ environment:

```sh
python3 -m venv .build/dmg-tools
.build/dmg-tools/bin/python3 -m pip install dmgbuild==1.6.7
.build/dmg-tools/bin/python3 script/build_local_dmg.py
```

The script packages the existing signed app, verifies file and symlink equality, checks the Applications link and Finder layout, and verifies the packaged app's signature. Existing outputs are refused. Use `--app` and `--output` for alternate paths.

## Apple-signed releases and automatic updates

An Apple Development or Developer ID Application identity enables the ServiceManagement registration route and team-anchored XPC authentication:

```sh
GLEE_SIGN_IDENTITY="YOUR_IDENTITY" ./script/build_and_run.sh --build-only
```

Developer ID distribution additionally requires notarization. Configure Glee's own HTTPS appcast, Ed25519 public key, and Apple team before publishing signed automatic updates. Signed builds bundle Sparkle and its license; local builds use manual updates. The release preparation script never publishes during tests.

## Publish a release

Use the universal app ZIP from a successful **macOS build and tests** run of the release commit. Verify both architecture slices, the bundle signature, version/build metadata, and the bundled Glee notice before packaging a DMG.

Publish the DMG, ZIP, and SHA-256 checksums together in GitHub Releases. Create the release tag from the verified source commit. Local helper installers are generated on each receiving Mac and are not included as shared installers. Apple notarization and signed automatic updates are separate release options.
