from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_local_helper_pkg as builder


APP_HASHES = {"arm64": "a" * 40, "x86_64": "b" * 40}
HELPER_HASHES = {"arm64": "c" * 40, "x86_64": "d" * 40}


class LocalHelperPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "Glee app with spaces.app"
        self.executable = self.app / "Contents/MacOS/Glee"
        self.helper = self.app / "Contents/Library/HelperTools/GleeHelper"
        self.executable.parent.mkdir(parents=True)
        self.helper.parent.mkdir(parents=True)
        self.executable.write_bytes(b"test-app-signed-by-fixture")
        self.helper.write_bytes(b"test-helper-signed-by-fixture")
        with (self.app / "Contents/Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleIdentifier": builder.APP_ID, "CFBundleExecutable": "Glee"}, handle)
        self.output = self.root / "Glee Local Helper.pkg"
        self.package_inspector = None
        self.external_calls = []

    def fake_external(self, arguments, **options):
        arguments = [str(value) for value in arguments]
        self.external_calls.append(arguments)
        self.assertTrue(options["check"])
        self.assertTrue(options["capture_output"])
        self.assertTrue(options["text"])
        if arguments[0] == "/usr/bin/lipo":
            return subprocess.CompletedProcess(arguments, 0, "arm64 x86_64\n", "")
        if arguments[0] == "/usr/bin/codesign":
            if "-d" in arguments:
                arch = arguments[arguments.index("--arch") + 1]
                is_app = Path(arguments[-1]).name == "Glee"
                identifier = builder.APP_ID if is_app else builder.SERVICE
                value = (APP_HASHES if is_app else HELPER_HASHES)[arch]
                return subprocess.CompletedProcess(arguments, 0, "", "Identifier=" + identifier + "\nCDHash=" + value + "\n")
            return subprocess.CompletedProcess(arguments, 0, "", "valid signature")
        if arguments[0] == "/usr/bin/pkgbuild":
            if self.package_inspector:
                self.package_inspector(arguments)
            Path(arguments[-1]).write_bytes(b"mock unsigned local package")
            return subprocess.CompletedProcess(arguments, 0, "created package", "")
        self.fail("Unexpected subprocess: " + repr(arguments))

    def build(self, **overrides):
        options = {"app": self.app, "output": self.output, "owner_uid": 501}
        options.update(overrides)
        with patch.object(builder.subprocess, "run", side_effect=self.fake_external):
            return builder.build_package(**options)

    def test_per_architecture_manifest_matches_the_copied_helper_and_owner(self):
        def inspect(arguments):
            resources = Path(arguments[arguments.index("--scripts") + 1]) / "resources"
            manifest = plistlib.loads((resources / "identity.pending.plist").read_bytes())
            self.assertEqual(manifest, {"formatVersion": 1, "ownerUID": 501,
                                       "appCodeHashes": list(APP_HASHES.values()),
                                       "helperCodeHashes": list(HELPER_HASHES.values())})
            self.assertFalse((resources / "identity.plist").exists())
            copied = resources / "GleeHelper"
            self.assertEqual(copied.read_bytes(), self.helper.read_bytes())
            self.assertEqual(copied.stat().st_mode & 0o777, 0o755)
            self.assertEqual(sorted(path.name for path in resources.rglob("*") if path.is_file()),
                             ["GleeHelper", "daemon.plist", "identity.pending.plist"])
            self.assertNotIn("--sign", arguments)
            self.assertIn("--nopayload", arguments)
            self.assertNotIn("--root", arguments)
            self.assertNotIn("--ownership", arguments)
        self.package_inspector = inspect
        original = {str(path.relative_to(self.app)): path.read_bytes() for path in self.app.rglob("*") if path.is_file()}
        self.assertEqual(self.build(), self.output.resolve())
        self.assertEqual(self.output.read_bytes(), b"mock unsigned local package")
        self.assertEqual(original, {str(path.relative_to(self.app)): path.read_bytes() for path in self.app.rglob("*") if path.is_file()})
        displayed = [call for call in self.external_calls if "--arch" in call]
        self.assertEqual({call[call.index("--arch") + 1] for call in displayed}, {"arm64", "x86_64"})

    def test_daemon_exposes_only_the_fixed_root_helper_service(self):
        configuration = builder.daemon_configuration()
        self.assertEqual(configuration["Label"], builder.SERVICE)
        self.assertEqual(configuration["ProgramArguments"], [str(builder.HELPER_PATH)])
        self.assertEqual(configuration["MachServices"], {builder.SERVICE: True})
        self.assertEqual(configuration["UserName"], "root")
        self.assertTrue(configuration["RunAtLoad"])
        self.assertTrue(configuration["KeepAlive"])
        self.assertEqual(configuration["ThrottleInterval"], 5)
        self.assertEqual(configuration["Umask"], 0o077)

    def test_invalid_uid_cannot_authorize_root_or_overflow_uid_t(self):
        for value in (0, -1, "-1", "", "501;id", "0", True, 2**32 - 1, 2**32, 501.5):
            with self.subTest(value=value), self.assertRaises(ValueError):
                builder.identity_manifest(value, ["a" * 40], ["b" * 40])
        with patch.object(builder.os, "getuid", return_value=0), self.assertRaises(ValueError):
            builder.validate_owner_uid()
        with patch.object(builder.os, "getuid", return_value=502):
            self.assertEqual(builder.validate_owner_uid(), 502)

    def test_manifest_rejects_ambiguous_or_non_hex_code_hashes(self):
        for values in ([], ["a" * 39], ["A" * 40], ["z" * 40], ["a" * 40] * 2,
                       [format(value, '040x') for value in range(5)], [{}], "a" * 40):
            with self.subTest(values=values), self.assertRaises(ValueError):
                builder.identity_manifest(501, values, ["b" * 40])

    def test_lipo_failure_or_ambiguous_architecture_stops_pinning(self):
        for text in ("", "arm64 arm64", "--arch", "arm64;id"):
            with self.subTest(text=text), patch.object(builder, "run", return_value=subprocess.CompletedProcess([], 0, text, "")), self.assertRaises(ValueError):
                builder.code_hashes(self.executable, builder.APP_ID)

    def test_wrong_identifier_missing_or_duplicate_hash_refuses_pin(self):
        for display in ("Identifier=other.app\nCDHash=" + "a" * 40,
                        "Identifier=" + builder.APP_ID + "\nCandidateCDHash=" + "a" * 40,
                        "Identifier=" + builder.APP_ID + "\nCDHash=" + "a" * 64,
                        "Identifier=" + builder.APP_ID + "\nCDHash=" + "a" * 40 + "\nCDHash=" + "b" * 40):
            with self.subTest(display=display), patch.object(builder, "run", side_effect=[
                    subprocess.CompletedProcess([], 0, "arm64", ""),
                    subprocess.CompletedProcess([], 0, "", display)]), self.assertRaises(ValueError):
                builder.code_hashes(self.executable, builder.APP_ID)

    def test_codesign_uppercase_hash_is_normalized_before_manifest(self):
        with patch.object(builder, "run", side_effect=[subprocess.CompletedProcess([], 0, "arm64", ""),
                subprocess.CompletedProcess([], 0, "", "Identifier=" + builder.APP_ID + "\nCDHash=" + "A" * 40)]):
            self.assertEqual(builder.code_hashes(self.executable, builder.APP_ID), ["a" * 40])

    def test_symlinked_app_or_helper_is_rejected_without_external_calls(self):
        alias = self.root / "Alias.app"
        alias.symlink_to(self.app, target_is_directory=True)
        with patch.object(builder.subprocess, "run") as external, self.assertRaises(ValueError):
            builder.build_package(app=alias, output=self.output, owner_uid=501)
        external.assert_not_called()
        target = self.root / "unrelated-helper"
        self.helper.rename(target)
        self.helper.symlink_to(target)
        with patch.object(builder.subprocess, "run") as external, self.assertRaises(ValueError):
            builder.build_package(app=self.app, output=self.output, owner_uid=501)
        external.assert_not_called()

    def test_wrong_bundle_identity_is_rejected(self):
        with (self.app / "Contents/Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleIdentifier": "com.example.OtherApp", "CFBundleExecutable": "OtherApp"}, handle)
        with patch.object(builder.subprocess, "run") as external, self.assertRaises(ValueError):
            builder.build_package(app=self.app, output=self.output, owner_uid=501)
        external.assert_not_called()

    def test_output_cannot_mutate_the_source_app_even_when_parent_is_missing(self):
        output = self.app / "Contents/New Package/Install.pkg"
        with self.assertRaises(ValueError):
            self.build(output=output)
        self.assertFalse(output.parent.exists())

    def test_existing_or_dangling_output_is_never_replaced(self):
        self.output.write_bytes(b"preserved")
        with patch.object(builder.subprocess, "run") as external, self.assertRaises(FileExistsError):
            builder.build_package(app=self.app, output=self.output, owner_uid=501)
        external.assert_not_called()
        self.assertEqual(self.output.read_bytes(), b"preserved")
        self.output.unlink()
        self.output.symlink_to(self.root / "missing")
        with self.assertRaises(FileExistsError):
            self.build()
        self.assertTrue(self.output.is_symlink())

    def test_concurrent_output_creation_does_not_overwrite_or_publish_partial_package(self):
        self.package_inspector = lambda arguments: self.output.write_bytes(b"another-process-package")
        with self.assertRaises(FileExistsError):
            self.build()
        self.assertEqual(self.output.read_bytes(), b"another-process-package")
        self.assertFalse(list(self.root.glob(".glee-local-helper-*")))

    def test_verification_failure_does_not_create_installer(self):
        with patch.object(builder.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "codesign")), self.assertRaises(subprocess.CalledProcessError):
            builder.build_package(app=self.app, output=self.output, owner_uid=501)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob(".glee-local-helper-*")))

    def test_concurrent_app_rebuild_cannot_silently_change_the_authorized_binary(self):
        with patch.object(builder.subprocess, "run", side_effect=self.fake_external), patch.object(builder, "code_hashes", side_effect=[
                ["a" * 40], ["c" * 40], ["b" * 40]]), self.assertRaisesRegex(ValueError, "app changed"):
            builder.build_package(app=self.app, output=self.output, owner_uid=501)
        self.assertFalse(self.output.exists())
        self.assertFalse(any(call[0] == "/usr/bin/pkgbuild" for call in self.external_calls))

    def test_scripts_guard_recovery_and_kernel_boolean_before_any_service_change(self):
        for name, contents in builder.installer_scripts().items():
            with self.subTest(script=name):
                self.assertIn("[[ ! -e \"$JOURNAL\" && ! -L \"$JOURNAL\" ]]", contents)
                self.assertIn('count == 1 && safe == 1', contents)
                self.assertIn('No[[:space:]]*$', contents)
                self.assertIn("'app.wakebee.helper' 'com.awakemac.helper'", contents)
                self.assertIn('[[ "$status" == 113 ]]', contents)
                self.assertIn('check_acl "$item"', contents)
                self.assertNotIn("pmset -a", contents)
                self.assertNotIn("osascript", contents)
                self.assertNotIn("spctl --master-disable", contents)
                self.assertNotIn("csrutil", contents)
        pre = builder.installer_scripts()["preinstall"]
        self.assertTrue(pre.endswith("require_safe_state\nstop_local_service\nrequire_safe_state\n"))
        post = builder.installer_scripts()["postinstall"]
        self.assertLess(post.index('/bin/chmod 0755 "$HELPER_TEMP"'), post.index('/bin/mv -f "$PENDING" "$MANIFEST"'))
        self.assertLess(post.index('/bin/mv -f "$PENDING" "$MANIFEST"'), post.index('/bin/launchctl bootstrap system "$DAEMON"'))
        acl_clear = next(line for line in post.splitlines() if line.startswith('/bin/chmod -N '))
        self.assertNotIn('/Library/PrivilegedHelperTools', acl_clear)
        self.assertNotIn('/Library/LaunchDaemons', acl_clear)
        self.assertLess(post.index('/bin/chmod -N '), post.index('/bin/mv -f "$PENDING" "$MANIFEST"'))
        self.assertLess(post.index('/bin/mv -f "$HELPER_TEMP" "$HELPER"'), post.index('/bin/mv -f "$PENDING" "$MANIFEST"'))
        self.assertLess(post.index('/bin/mv -f "$DAEMON_TEMP" "$DAEMON"'), post.index('/bin/mv -f "$PENDING" "$MANIFEST"'))
        self.assertIn('/usr/bin/mktemp ', post)
        self.assertIn('check_file "$HELPER_TEMP"', post)
        self.assertNotIn('/usr/sbin/chown ', post)

    def test_acl_guard_preserves_legitimate_deny_delete_but_rejects_all_mutation(self):
        metadata = 'drwxr-xr-x+  5 root  wheel  160 Oct 16 12:00 /Library\n'
        fixtures = [
            (metadata, True),
            (metadata + ' 0: group:everyone deny delete\n', True),
            (metadata + ' 0: group:everyone inherited allow list,search,readattr,readextattr,readsecurity\n', True),
            (metadata + ' 0: group:everyone allow read,execute,file_inherit,directory_inherit,only_inherit\n', True),
            (metadata + ' 0: user:somebody allow write\n', False),
            (metadata + ' 0: group:staff allow add_file,add_subdirectory,delete_child\n', False),
            (metadata + ' 0: group:everyone allow writeattr,writeextattr\n', False),
            (metadata + ' 0: group:everyone allow writesecurity,chown\n', False),
            (metadata + ' 0: group:everyone allow append\n', False),
            (metadata + ' 0: group:everyone allow future_unknown_right\n', False),
            (metadata + ' 0: group:everyone strange read\n', False),
            (metadata + ' 0: group:everyone deny delete\n 1: user:attacker allow write\n', False),
        ]
        for fixture, safe in fixtures:
            with self.subTest(acl=fixture):
                result = subprocess.run(['/usr/bin/awk', builder.ACL_CHECK_PROGRAM], input=fixture,
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode == 0, safe, result.stderr)

    def test_kernel_sleep_guard_rejects_missing_ambiguous_or_non_boolean_values(self):
        program = re.search(r"state=\$\(/usr/bin/awk '(.*?)' <<< \"\$registry\"\)",
                            builder.SCRIPT_GUARDS, flags=re.DOTALL).group(1)
        for fixture, expected in (("      \"SleepDisabled\" = No\n", "normal"),
                                  ("      \"SleepDisabled\" = Yes\n", "unknown-or-disabled"),
                                  ("      \"SleepDisabled\" = 0\n", "unknown-or-disabled"),
                                  ("      \"SleepDisabled\" = \"No\"\n", "unknown-or-disabled"),
                                  ("      \"SleepDisabled\" = No\n \"SleepDisabled\" = Yes\n", "unknown-or-disabled"),
                                  ("      \"SleepDisabled\" = No\n \"SleepDisabled\" = No\n", "unknown-or-disabled"),
                                  ("unrelated property = No\n", "unknown-or-disabled")):
            with self.subTest(registry=fixture):
                result = subprocess.run(['/usr/bin/awk', program], input=fixture,
                                        text=True, capture_output=True, check=True)
                self.assertEqual(result.stdout.strip(), expected)

    def test_only_the_exact_loaded_local_daemon_path_can_be_stopped(self):
        program = re.search(r"loaded_path=\$\(/usr/bin/awk '(.*?)' <<< \"\$description\"\)",
                            builder.SCRIPT_GUARDS, flags=re.DOTALL).group(1)
        local_path = '\tpath = /Library/LaunchDaemons/com.dumpydon.glee.helper.plist\n'
        for fixture, expected in ((local_path, 'local'),
                                  ('\tpath = /Applications/Glee.app/Contents/Library/LaunchDaemons/com.dumpydon.glee.helper.plist\n', 'other-or-unknown'),
                                  ('', 'other-or-unknown'),
                                  (local_path + local_path, 'other-or-unknown'),
                                  ('\tpath = /Library/LaunchDaemons/com.dumpydon.glee.helper.plist-extra\n', 'other-or-unknown')):
            with self.subTest(service=fixture):
                result = subprocess.run(['/usr/bin/awk', program], input=fixture,
                                        text=True, capture_output=True, check=True)
                self.assertEqual(result.stdout.strip(), expected)

    def test_uninstall_has_no_payload_and_only_removes_exact_local_product_files(self):
        def inspect(arguments):
            self.assertIn("--nopayload", arguments)
            self.assertNotIn("--root", arguments)
            scripts = Path(arguments[arguments.index("--scripts") + 1])
            post = (scripts / "postinstall").read_text()
            self.assertIn('/bin/rm -f "$DAEMON" "$HELPER" "$MANIFEST" "$PENDING"', post)
            self.assertNotIn("rm -rf", post)
            self.assertNotIn('rm -f "$JOURNAL"', post)
            self.assertIn('/bin/rmdir "$CONFIG_DIR"', post)
            self.assertNotIn("/bin/launchctl bootstrap", post)
        self.package_inspector = inspect
        with patch.object(builder.subprocess, "run", side_effect=self.fake_external):
            builder.build_package(output=self.output, uninstall=True)
        self.assertEqual(self.output.read_bytes(), b"mock unsigned local package")

    def test_generated_scripts_have_valid_bash_syntax(self):
        for uninstall in (False, True):
            for name, contents in builder.installer_scripts(uninstall).items():
                script = self.root / (name + str(uninstall))
                script.write_text(contents)
                subprocess.run(["/bin/bash", "-n", str(script)], check=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
