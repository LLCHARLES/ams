from pathlib import Path
import subprocess
import tempfile

check = Path(__file__).resolve().parents[2] / "scripts/check-layers.sh"
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / "Native").mkdir()
    source = root / "Native/fixture.m"
    for directive in ('\t#  import <Redesigned/Foo.h>', '#include"App/Foo.h"',
                      '  # include\t<App/Foo.h>', '#import "Redesigned/Foo.h"'):
        source.write_text(directive + "\n")
        result = subprocess.run([check, root], capture_output=True, text=True)
        if result.returncode != 1 or directive not in result.stderr:
            raise SystemExit(f"missed violation: {directive}")
    source.write_text('#import "Native/Same.h"\n #include <UIKit/UIKit.h>\n// #import "App/Foo.h"\n')
    subprocess.run([check, root], check=True)
print("layer fixtures: ok")
