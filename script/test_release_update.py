"""Publication failures must stop before any public release or feed mutation."""
import argparse
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import release_update as release


class PublicationTests(unittest.TestCase):
    def fixture(self, directory):
        output = Path(directory)
        archive = output / "Glee-0.12.0.zip"
        archive.write_bytes(b"test archive")
        appcast = output / "appcast.xml"
        appcast.write_bytes(b"test signed feed")
        (output / "notes.md").write_text("Test release notes.")
        manifest = {"version": "0.12.0", "tag": "v0.12.0", "archive": archive.name,
                    "archive_sha256": release.digest(archive), "feed_sha256": release.digest(appcast),
                    "previous_feed_sha": "previous", "public_key": "public"}
        (output / "release.json").write_text(json.dumps(manifest))
        return output

    def test_altered_archive_never_reaches_upload(self):
        with tempfile.TemporaryDirectory() as directory:
            output = self.fixture(directory)
            (output / "Glee-0.12.0.zip").write_bytes(b"changed archive")
            with patch.object(release, "configuration", return_value={"SUPublicEDKey": "public"}), \
                    patch.object(release, "run") as run:
                with self.assertRaisesRegex(ValueError, "Prepared release changed"):
                    release.publish(argparse.Namespace(directory=output))
                run.assert_not_called()

    def test_concurrent_feed_change_never_creates_release(self):
        with tempfile.TemporaryDirectory() as directory:
            output = self.fixture(directory)
            with patch.object(release, "configuration", return_value={"SUPublicEDKey": "public"}), \
                    patch.object(release, "current_feed", return_value=("newer", b"feed")), \
                    patch.object(release, "run") as run:
                with self.assertRaisesRegex(ValueError, "public feed changed"):
                    release.publish(argparse.Namespace(directory=output))
                self.assertTrue(all(call.args[0] != "gh" for call in run.call_args_list))

    def test_archive_published_before_feed_update(self):
        with tempfile.TemporaryDirectory() as directory:
            output = self.fixture(directory)
            with patch.object(release, "configuration", return_value={"SUPublicEDKey": "public"}), \
                    patch.object(release, "current_feed", return_value=("previous", b"feed")), \
                    patch.object(release, "run") as run:
                release.publish(argparse.Namespace(directory=output, notes_file=output / "notes.md"))
                operations = [call for call in run.call_args_list if call.args[0] == "gh"]
                self.assertEqual([call.args[1:3] for call in operations],
                                 [("release", "create"), ("release", "edit"), ("api", "--method")])
                payload = json.loads(operations[-1].kwargs["input"])
                self.assertEqual(payload["sha"], "previous")
                self.assertEqual(payload["branch"], "main")

    def test_tester_release_is_not_marked_as_latest_stable(self):
        with tempfile.TemporaryDirectory() as directory:
            output = self.fixture(directory)
            with patch.object(release, "configuration", return_value={"SUPublicEDKey": "public"}), \
                    patch.object(release, "current_feed", return_value=("previous", b"feed")), \
                    patch.object(release, "run") as run:
                release.publish(argparse.Namespace(directory=output, prerelease=True, notes_file=output / "notes.md"))
                edit = next(call for call in run.call_args_list if call.args[:3] == ("gh", "release", "edit"))
                self.assertIn("--prerelease", edit.args)
                self.assertIn("--latest=false", edit.args)


if __name__ == "__main__":
    unittest.main()
