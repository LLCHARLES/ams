import pathlib
import struct
import subprocess
import sys
import tempfile
import unittest


class InsertDylib(unittest.TestCase):
    def test_existing_required_load(self):
        script = pathlib.Path(__file__).resolve().parents[1] / "scripts/insert-dylib.py"
        name = "@rpath/X.dylib"
        for command, offset in ((0x80000018, 24), (0x8000001F, 24), (0x80000018, 28), (0x20, 24)):
            with self.subTest(command=command, offset=offset), tempfile.TemporaryDirectory() as tmp:
                modern = offset == 28
                load = struct.pack("<6I", command, 48, offset, 0x1A741800 if modern else 0, 0, 0)
                if modern:
                    load += struct.pack("<I", 1)
                load = (load + name.encode()).ljust(48, b"\0")
                image = struct.pack("<8I", 0xFEEDFACF, 0x100000C, 0, 2, 1, len(load), 0, 0) + load + bytes(128)
                binary = pathlib.Path(tmp) / "fixture"
                binary.write_bytes(image)
                subprocess.run([sys.executable, script, binary, name], check=True)
                self.assertEqual(binary.read_bytes(), image)


if __name__ == "__main__":
    unittest.main()
