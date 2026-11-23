"""Common compiler inputs for the two simulator settings fixtures."""
from companion_build import include_directories
from generate_target import generate_headers
from pixie_target import ROOT, V9190

def fixture_includes(out):
    headers = out / "include"
    generate_headers(headers, V9190)
    return ["-I" + str(p) for p in include_directories(headers)]

SOURCES = [ROOT / name for name in (
    "tests/admitted_host.c", "src/UI/PixieManagerSettings.m", "src/UI/PixiePageController.m",
    "src/UI/Localization.m", "src/Diagnostics/DiagnosticsPreferences.m",
    "src/Diagnostics/DiagnosticTrace.m", "src/Diagnostics/NativeKeyTrace.m",
    "src/Spotify/WireProto.m", "tests/trace_platform_stub.m", "tests/SettingsFixtureActions.m",
)]
