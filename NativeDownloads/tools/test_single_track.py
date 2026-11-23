"""Focused host regression: production download, selected-menu and library paths."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="pixie-single-track-") as temporary:
    subprocess.run([sys.executable, "-B", root / "tools/test14.py", "--fixture",
                    "retrine_track_download", "--build-dir", temporary], check=True)
