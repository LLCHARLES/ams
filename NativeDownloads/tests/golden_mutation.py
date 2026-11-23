"""Prove the frozen golden runner rejects one changed patch byte/header.

Mutation happens only in a disposable copy; the real source and expected hashes
are never rewritten. The child must fail an assertion, not import or compile.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="pixie-golden-mutation-") as temporary:
    project=Path(temporary)
    native=project/"NativeDownloads"
    shutil.copytree(ROOT/"tools",native/"tools",ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copytree(ROOT/"targets",native/"targets")
    (native/"tests").mkdir()
    shutil.copy2(ROOT/"tests/patch_goldens.py",native/"tests/patch_goldens.py")
    (project/"ipa").symlink_to(ROOT.parent/"ipa",target_is_directory=True)
    target=native/"tools/patch_native_restrictions.py"
    original=target.read_text()
    cases=[
        ("header","Goldens.test_headers",
         "SAPRestrictionCaveOffset=0x{cave-profile.preferred:x}",
         "SAPRestrictionCaveOffset=0x{cave-profile.preferred+1:x}"),
        ("patch byte","Goldens.test_entire_executable",
         "    return bytes(result), {'setter': hex(setter)",
         "    result[target] ^= 1\n    return bytes(result), {'setter': hex(setter)"),
    ]
    for label,test,before,after in cases:
        if original.count(before)!=1:raise AssertionError("Mutation site changed: "+label)
        target.write_text(original.replace(before,after))
        result=subprocess.run([sys.executable,"-B",str(native/"tests/patch_goldens.py"),test],
                              capture_output=True,text=True,timeout=30)
        if result.returncode!=1 or "AssertionError" not in result.stderr or "FAILED (failures=1)" not in result.stderr:
            raise AssertionError("Golden mutation did not fail at its comparison:\n"+result.stdout+result.stderr)
        print("PASS frozen golden detects changed "+label)
