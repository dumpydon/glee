import subprocess
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

import check_build_destination as guard


class BuildDestinationTests(unittest.TestCase):
    def test_running_destination_is_never_replaced(self):
        executable = "/Applications/OtherApp.app/Contents/MacOS/OtherApp"
        with self.assertRaisesRegex(RuntimeError, "Refusing to replace"):
            guard.require_idle_destination(executable, ["  " + executable])

    def test_separate_release_build_does_not_interrupt_installed_app(self):
        guard.require_idle_destination(
            "/tmp/release/OtherApp.app/Contents/MacOS/OtherApp",
            ["/Applications/OtherApp.app/Contents/MacOS/OtherApp"])

    def test_symlink_cannot_hide_a_running_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            actual = root / "Awake Mac.app"
            actual.mkdir()
            alias = root / "Alias.app"
            alias.symlink_to(actual, target_is_directory=True)
            with self.assertRaises(RuntimeError):
                guard.require_idle_destination(alias / "Contents/MacOS/OtherApp",
                    [str(actual / "Contents/MacOS/OtherApp")])

    def test_helper_and_other_apps_do_not_block_a_separate_build(self):
        guard.require_idle_destination("/tmp/OtherApp.app/Contents/MacOS/OtherApp",
            ["Contents/Library/HelperTools/OtherAppHelper", "/Applications/Other.app/Contents/MacOS/Other"])

    def test_failed_process_inspection_stops_the_build(self):
        with patch.object(guard.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "ps")):
            with self.assertRaises(subprocess.CalledProcessError):
                guard.check("/tmp/OtherApp.app/Contents/MacOS/OtherApp")

    def test_rebrand_cannot_overwrite_the_running_old_executable(self):
        with self.assertRaisesRegex(RuntimeError, "Refusing to replace"):
            guard.require_idle_destination(
                "/Applications/OtherApp.app/Contents/MacOS/Glee",
                ["/Applications/OtherApp.app/Contents/MacOS/OtherApp"])

    def test_rebranded_build_can_be_staged_separately(self):
        guard.require_idle_destination(
            "/tmp/release/Glee.app/Contents/MacOS/Glee",
            ["/Applications/OtherApp.app/Contents/MacOS/OtherApp"])


if __name__ == "__main__":
    unittest.main()
