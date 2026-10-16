"""Resolve local profile aliases without reading or copying Keychain credentials."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def resolve_profile(name, aliases_path=None):
    path = aliases_path or ROOT / '.notary-profile-aliases.json'
    aliases = json.loads(path.read_text()) if path.exists() else {}
    target = aliases.get(name, name)
    if not isinstance(target, str) or not target.strip():
        raise ValueError('Invalid notarization profile alias.')
    return target
