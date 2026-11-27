"""Numbered clip fixture and compositor-side oracle, shared by the two page apps."""
from pathlib import Path
import re
import subprocess as sp
import sys
from PIL import Image, ImageDraw, ImageChops, ImageStat


def fixture(out):
    for name in ("motion-fixture", "replacement"):
        frames = []
        for n in range(8):
            color = (22, 50, 224) if name == "replacement" else ((35, 205, 55) if n == 3 else (197, 44, 30))
            im = Image.new("RGB", (720, 540), color)
            d = ImageDraw.Draw(im)
            # Offset, asymmetric bands cross the aspect-fill cut. Equal frame
            # numbers alone must not excuse wrong cropping, gravity or scrim.
            d.rectangle((0, 205, 110, 500), fill="orange")
            d.rectangle((510, 298, 718, 358), fill="aqua")
            d.text((290, 285), str(n), fill="white", font_size=110)
            frames.append(im.tobytes())
        rotated = name == "motion-fixture"
        mp4 = out / (name + ".mp4")
        stored = out / "sideways.mp4" if rotated else mp4
        sp.run(["ffmpeg", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "720x540",
                "-r", "1", "-i", "-", "-vf", "transpose=clock,fps=24" if rotated else "fps=24",
                "-c:v", "libx264", "-pix_fmt", "yuv420p", str(stored)], input=b"".join(frames), check=True)
        if rotated:
            sp.run(["ffmpeg", "-loglevel", "error", "-display_rotation", "90", "-i", str(stored),
                    "-c", "copy", str(mp4)], check=True)


def run(sim, bundle, out):
    launch = sp.Popen([sys.executable, Path(__file__).resolve().parents[1] / "sim-launch.py",
                       "--live", "--timeout", "100", sim, bundle, "motion-visibility"],
                      stdout=sp.PIPE, stderr=sp.STDOUT, text=True, errors="replace")
    seen = {}
    try:
        for line in launch.stdout:
            if "[harness]" not in line:
                continue
            print(line.strip(), flush=True)
            if "[harness] FAIL" in line:
                raise RuntimeError(line.strip())
            if "[harness] PASS" in line and "header playback:" in line:
                if set(seen) != set("poster held-first last cancel-strip return-strip cancel exposed seeking failed-seek unready resumed reduce replacement failed-capture".split()):
                    raise RuntimeError("missing a compositor sample")
                return
            marker = re.search(r"\[harness\] FRAME (\S+) (\d+) (\d+) (\d+) (\d+) (.*)", line.strip())
            if not marker:
                continue
            name, x, y, w, h, pipe = marker.groups()
            x, y, w, h = map(int, (x, y, w, h))
            png = out / (bundle + "-" + name + ".png")
            sp.run(["xcrun", "simctl", "io", sim, "screenshot", str(png)], check=True, capture_output=True)
            screen = Image.open(png).convert("RGB")
            crop = (x+3, y+3, x+w-3, y+h-3)
            im = screen.crop(crop)
            r, g, b = im.getpixel((im.width//3, im.height//3))
            if name == "last" and not (g > 2*r and g > 2*b):
                raise RuntimeError(f"{name}: expected green frame 3, saw {(r,g,b)}")
            if name == "held-first" and not (r > 2*g and r > 2*b):
                raise RuntimeError(f"{name}: expected paused red frame zero, saw {(r,g,b)}")
            if name == "replacement" and not (b > 2*r and b > 2*g):
                raise RuntimeError(f"{name}: stale or missing replacement, saw {(r,g,b)}")
            if name == "poster" and not (r > 120 and b > 120 and g < 60):
                raise RuntimeError(f"{name}: missing magenta poster, saw {(r,g,b)}")
            if name not in ("last", "replacement", "held-first"):
                if name in ("poster", "failed-capture"):
                    offset = round(w / 240 * 200)
                    ref = screen.crop((crop[0], crop[1]+offset, crop[2], crop[3]+offset))
                else:
                    ref = seen["last"]
                if name.endswith("-strip"):
                    strip = (0, 0, round(w / 240 * 16), im.height)
                    ref, im = ref.crop(strip), im.crop(strip)
                diff = ImageStat.Stat(ImageChops.difference(ref, im))
                if max(diff.mean) > 3 or max(diff.rms) > 10:
                    points = [(ref.getpixel((x, y)), im.getpixel((x, y))) for x, y in
                              [(10, 10), (ref.width//3, ref.height//3), (10, ref.height//2), (ref.width-10, ref.height//2)]]
                    raise RuntimeError(f"{name}: frame/crop/scrim differs: mean={diff.mean} rms={diff.rms} samples={points}")
            seen[name] = im
            with open(pipe, "wb", buffering=0) as ack:
                ack.write(b"+")
        raise RuntimeError("app exited without its verdict")
    finally:
        launch.terminate()
        launch.wait()


if sys.argv[1] == "fixture":
    fixture(Path(sys.argv[2]))
else:
    run(sys.argv[1], sys.argv[2], Path(sys.argv[3]))
