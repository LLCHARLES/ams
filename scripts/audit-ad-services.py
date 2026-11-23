#!/usr/bin/env python3
"""Audit Retrine's service hook coverage against inspected decrypted Spotify IPAs."""
import argparse
import importlib.util
import json
import plistlib
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tweak/Sources/Shared/AdBlock/AdServices.x"
EXPECTED_GATES = json.loads((ROOT / "harness/adblock/service-gates.json").read_text())
spec = importlib.util.spec_from_file_location("transport", ROOT / "scripts/spotify-transport-scan.py")
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)

# Adapted from EeveeSpotifyReincarnated (GPL-3), 1010573, 7a617a7 and e2abe5a.
# Unlike a string-presence audit, a covered entry must name an instance selector
# in the actual class metadata, and be in the table consumed by installServices.
SERVICE = re.compile(r"(Ads|AdSlot|InStream|Upsell|Leavebehind|Sponsored|RealTimeAd|AudioAd).*Service")
PROTECTED = {
    "_TtC19AdsPlatform_DSAImpl14DSAServiceImpl": "regulatory notices",
    "_TtC24AdsPlatform_ComScoreImpl19ComScoreServiceImpl": "upstream DI/measurement exemption",
    "_TtC25PremiumUpsell_PremiumImpl14PremiumService": "required Premium DI",
    "_TtC26CulturalMoments_UpsellImpl17UpsellServiceImpl": "upstream non-ad/DI exemption",
    "_TtC27AdsPlatform_AdsFeedbackImpl22AdsFeedbackServiceImpl": "ad feedback",
    "_TtC30Jam_AdsDisclaimerSheetPageImpl29AdsDisclaimerSheetPageService": "legal disclaimer",
    "_TtC31AdsPlatform_AdsInAppBrowserImpl22AdsInAppBrowserService": "required browser DI",
    "_TtC34AdsPlatform_MobiusAdsUtilitiesImpl29MobiusAdsUtilitiesServiceImpl": "required utilities DI",
    "_TtC35AdsPlatform_AdsIdentityTrackingImpl33AdsIdentityTrackingSessionService": "required identity DI",
    "_TtC35AdsPlatform_AdsIdentityTrackingImpl37AdsIdentityPermissionRequestorService": "identity permission handling",
    "_TtC36AdsPlatform_AdsContextMenuButtonImpl31AdsContextMenuButtonServiceImpl": "ad context menu",
    "_TtC36AdsPlatform_AdsPreferencesConfigImpl31AdsPreferencesConfigServiceImpl": "preferences",
    "_TtC40AdsPlatform_AdsPreferencesDataLoaderImpl35AdsPreferencesDataLoaderServiceImpl": "preferences",
    "_TtC40PremiumUpsell_PremiumDestinationPageImpl29PremiumDestinationServiceImpl": "required destination DI",
}

# Explicitly checked 9.1.90 exceptions, not a blanket exemption for missing methods.
# These classes have no Objective-C -load. Never substitute dependency injection or
# an initializer for it. Existing legacy targets remain guarded for older versions.
NO_LOAD = {
    "_TtC19Upsells_ServiceImpl18UpsellsServiceImpl",
    "_TtC42AdsEmbedded_AdsSponsoredPlaylistHeaderImpl37AdsSponsoredPlaylistHeaderServiceImpl",
    "_TtC36AdsEmbedded_EmbeddedAdControllerImpl31EmbeddedAdControllerServiceImpl",
    "_TtC35AdsEmbedded_EmbeddedCTAElementsImpl30EmbeddedCTAElementsServiceImpl",
    "_TtC34AdsPlatform_AdsInstrumentationImpl29AdsInstrumentationServiceImpl",
    "_TtC23AdsPlatform_ElementImpl18ElementServiceImpl",
    "_TtC36AdsPlatform_RealTimeAdControllerImpl31RealTimeAdControllerServiceImpl",
    "_TtC36AdsStandalone_LeavebehindAdsBaseImpl33LeavebehindAdsBaseInternalService",
    "_TtC36AdsStandalone_LeavebehindAdsBaseImpl25LeavebehindAdsBaseService",
    "_TtC28ContextualShuffle_UpsellImpl40ShuffleToggleUpsellServiceImplementation",
    "_TtC21NativeAds_ElementImpl27NativeAdsElementServiceImpl",
    "_TtC20NativeAds_LoggerImpl26NativeAdsLoggerServiceImpl",
    "_TtC31PremiumUpsell_UpsellServiceImpl17UpsellServiceImpl",
    "_TtC40Referrals_ReferralsUpsellCardElementImpl37ReferralsUpsellCardElementServiceImpl",
    "_TtC31ReinventFree_DownloadUpsellImpl21DownloadUpsellService",
    "_TtC35ReinventFree_PlayFullSongUpsellImpl29PlayFullSongUpsellServiceImpl",
}

# The renamed owner is present on 9.2.0, the Swift owner on 9.1.90.
# The candidate/ABI checks still require the present owner to be covered.
ADS_BASE_OWNERS = {
    "_TtC28AdsPlatform_AdsBaseSwiftImpl23AdsBaseSwiftServiceImpl",
    "_TtC23AdsPlatform_AdsBaseImpl18AdsBaseServiceImpl",
}


def targets(source):
    text = re.sub(r"//[^\n]*|/\*.*?\*/", "", source.read_text(), flags=re.S)
    table = re.search(r"static const SGServiceTarget serviceTargets\[\]\s*=\s*\{(.*?)\n\};", text, re.S)
    if not table:
        raise ValueError("Missing installed service target table")
    entries = re.findall(r'\{"([^"]+)", "([^"]+)", (YES|NO)\},', table[1])
    remainder = re.sub(r'\{"[^"]+", "[^"]+", (?:YES|NO)\},', "", table[1])
    if remainder.strip() or not entries:
        raise ValueError("Unrecognized service target table entry")
    result = {}
    for name, selector, upsell in entries:
        if name in result:
            raise ValueError(f"Duplicate service target: {name}")
        result[name] = (selector, "upsells" if upsell == "YES" else "ads")
    return result


def method_encodings(binary, wanted):
    """Join otool's type encodings to dyld_info's selectors by class and IMP.

    Relative method lists in this IPA leave selector references unresolved in
    otool, while dyld_info resolves their names but omits their type encodings.
    """
    encodings = {}
    with tempfile.TemporaryFile(mode="w+") as output:
        subprocess.run(["xcrun", "otool", "-ov", str(binary)], stdout=output,
                       stderr=subprocess.PIPE, text=True, check=True)
        output.seek(0)
        name, in_methods, encoding = None, False, None
        for line in output:
            if re.match(r"^[0-9a-fA-F]{16} ", line):
                name, in_methods = None, False
            match = re.match(r"        name\s+0x[0-9a-fA-F]+ (\S+)\s*$", line)
            if match:
                name = match[1] if match[1] in wanted else None
                in_methods = False
            if not name:
                continue
            if re.match(r"        baseMethods\s", line):
                in_methods = True
                continue
            if re.match(r"        \S", line):
                in_methods = False
            if not in_methods:
                continue
            match = re.match(r"            types\s+0x[0-9a-fA-F]+(?: \(0x[0-9a-fA-F]+\))? (.+)\s*$", line)
            if match:
                encoding = match[1].strip()
            match = re.match(r"            imp\s+(0x[0-9a-fA-F]+)(?: \((0x[0-9a-fA-F]+)\))?", line)
            if match:
                if encoding is None:
                    raise ValueError(f"Method encoding missing in otool metadata: {name}")
                key = (name, int(match[2] or match[1], 16))
                encodings.setdefault(key, set()).add(encoding)
                encoding = None
    return encodings


def binary_classes(ipa):
    classes = {}
    with zipfile.ZipFile(ipa) as archive, tempfile.TemporaryDirectory(prefix="ad-service-audit-") as temp:
        info = plistlib.loads(transport.bounded_member(
            archive, "Payload/Spotify.app/Info.plist", transport.MAX_PLIST_BYTES))
        version = info.get("CFBundleShortVersionString")
        if version not in ("9.1.90", "9.2.0") or info.get("CFBundleIdentifier") != "com.spotify.client":
            raise ValueError("This audit requires the original Spotify 9.1.90 or 9.2.0 IPA")
        expected = transport.INSPECTED_UUIDS[version]
        if info.get("CFBundleVersion") != expected["build"]:
            raise ValueError(f"Spotify build differs from the inspected {version} IPA")
        for image in ("Spotify", "Frameworks/SpotifyShared.framework/SpotifyShared"):
            data = transport.bounded_member(archive, "Payload/Spotify.app/" + image, transport.MAX_IMAGE_BYTES)
            if transport.macho(data)["uuid"] != expected[image]:
                raise ValueError(f"Spotify image differs from the inspected {version} IPA: {image}")
            binary = Path(temp) / "image"
            binary.write_bytes(data)
            output = subprocess.run(["xcrun", "dyld_info", "-objc", str(binary)],
                                    check=True, capture_output=True, text=True).stdout
            image_classes = {}
            for name, parent, body in re.findall(
                    r"@interface\s+(\S+)\s*:\s*(\S+)[^\n]*\n(.*?)@end", output, re.S):
                methods = {selector: int(address, 16) for address, selector in re.findall(
                    r"(0x[0-9a-fA-F]+)\s+-\[[^\s]+ ([^\]]+)\]", body)}
                image_classes[name] = (parent, methods)
            encodings = method_encodings(binary, image_classes)
            for name, (parent, methods) in image_classes.items():
                typed = {}
                for selector, address in methods.items():
                    types = encodings.get((name, address), set())
                    # Ambiguous or undecoded metadata cannot prove an ABI.
                    typed[selector] = next(iter(types)) if len(types) == 1 else None
                classes[name] = (parent, typed)
    if not classes:
        raise ValueError("No Objective-C class metadata decoded")
    return classes


def selectors(classes, name):
    result, seen = {}, set()
    while name in classes and name not in seen:
        seen.add(name)
        name, methods = classes[name]
        for selector, encoding in methods.items():
            result.setdefault(selector, encoding)
    return result


def compatible(selector, encoding):
    # Same supported signatures as compatibleMethod: void, two implicit args,
    # and only registerScrollProviderIn: accepts one object argument.
    # Frame sizes and argument offsets are representation, not ABI differences.
    object_type = r'@(?:\?|"[^"]*")?'
    signature = r"v\d*" + object_type + r"\d*:\d*"
    if selector == "registerScrollProviderIn:":
        signature += object_type + r"\d*"
    return encoding is not None and re.fullmatch(signature, encoding) is not None


def audit(classes, hooked):
    candidates = {
        name for name in classes
        if name.startswith("_TtC") and SERVICE.search(name)
        and name.endswith(("Service", "ServiceImpl", "ServiceImplementation"))
    }
    errors, covered, exempt = [], [], []
    for name, (selector, gate) in sorted(hooked.items()):
        if EXPECTED_GATES.get(name) != gate:
            errors.append(f"Incorrect or unspecified gate: {name}: {gate}; expected {EXPECTED_GATES.get(name)}")
    for name in sorted(candidates):
        methods = selectors(classes, name)
        if name in PROTECTED:
            if name in hooked:
                errors.append(f"Protected service hooked: {name}")
            exempt.append(f"{name}: {PROTECTED[name]}")
        elif name in NO_LOAD:
            if "load" in methods:
                errors.append(f"Stale no-load exemption: {name}")
            if name in hooked and hooked[name][0] != "load":
                errors.append(f"Unverified alternate hook on no-load service: {name}")
            exempt.append(f"{name}: no Objective-C -load (not silenced)")
        elif name in hooked and compatible(hooked[name][0], methods.get(hooked[name][0])) and EXPECTED_GATES.get(name) == hooked[name][1]:
            covered.append(f"{name} -{hooked[name][0]}")
        else:
            errors.append(f"Uncovered intended service: {name}")
    for name, (selector, gate) in sorted(hooked.items()):
        if name not in classes:
            if name not in ADS_BASE_OWNERS or not ADS_BASE_OWNERS.intersection(classes):
                errors.append(f"Hook class absent from inspected IPA: {name}")
        elif selector not in selectors(classes, name) and not (name in NO_LOAD and selector == "load"):
            errors.append(f"Hook selector absent from inspected IPA: {name} -{selector}")
        elif selector in selectors(classes, name) and not compatible(selector, selectors(classes, name)[selector]):
            errors.append(f"Incompatible or unproven hook ABI: {name} -{selector}: {selectors(classes, name)[selector]}")
    if not candidates:
        errors.append("No ad/upsell services discovered")
    return covered, exempt, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--source", type=Path, default=SOURCE, help="isolated hook-table mutation input")
    args = parser.parse_args()
    try:
        covered, exempt, errors = audit(binary_classes(args.ipa), targets(args.source))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Ad service audit failed: {error}\n")
    for name in covered:
        print(f"COVERED {name}")
    for reason in exempt:
        print(f"EXEMPT {reason}")
    for error in errors:
        print(f"FAIL {error}")
    print(f"Spotify: {len(covered)} covered, {len(exempt)} exempt, {len(errors)} failures")
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
