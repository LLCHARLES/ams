"""Required source licenses shared by Pixie IPA and jailbreak packaging."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IPA_LICENSE_DIRECTORY = "Payload/Spotify.app/PixieNotices/"


def required_licenses():
    paths = {"LICENSE": ROOT.parent/"LICENSE",
             "M4A-NOTICES.md": ROOT/"vendor/M4A-NOTICES.md"}
    result = {}
    for name, path in paths.items():
        content = path.read_bytes()
        if not content.strip():
            raise ValueError(f"Required package license is empty: {path}")
        result[name] = content
    return result
