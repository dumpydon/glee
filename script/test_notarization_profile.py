import json
from pathlib import Path
import tempfile
import unittest
from notarization_profile import resolve_profile

class ProfileTests(unittest.TestCase):
    def test_alias_and_direct_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'aliases.json'
            self.assertEqual(resolve_profile('Glee-Notary', path), 'Glee-Notary')
            path.write_text(json.dumps({'Glee-Notary': 'existing-profile'}))
            self.assertEqual(resolve_profile('Glee-Notary', path), 'existing-profile')
            self.assertEqual(resolve_profile('other', path), 'other')
    def test_invalid_alias_fails_without_guessing(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'aliases.json'
            path.write_text('{"Glee-Notary": null}')
            with self.assertRaises(ValueError): resolve_profile('Glee-Notary', path)
