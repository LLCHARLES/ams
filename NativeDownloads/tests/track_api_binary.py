"""Verify the private API ABI against the supplied, unmodified Spotify 9.1.90."""
from pathlib import Path
import struct
import sys
import subprocess
import plistlib
from zipfile import ZipFile

if len(sys.argv)==1:
    for version in ("9.1.90","9.2.0"):
        subprocess.run([sys.executable,"-B",__file__,version],check=True)
    raise SystemExit(0)
version=sys.argv[1]
assert version in ("9.1.90","9.2.0")
old=version=="9.1.90"
ipa = Path(__file__).resolve().parents[2] / f"ipa/Spotify-{version}.ipa"
with ZipFile(ipa) as archive:
    data = archive.read("Payload/Spotify.app/Spotify")
    info=plistlib.loads(archive.read("Payload/Spotify.app/Info.plist"))
assert info["CFBundleShortVersionString"]==version
assert info["CFBundleVersion"]==("919002269" if old else "920002054")
def load_image(data):
    assert struct.unpack_from("<I", data)[0] == 0xFEEDFACF
    segments, sections = [], {}
    cursor = 32
    uuid = None
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<II", data, cursor)
        if command == 0x1B:
            uuid = data[cursor + 8:cursor + 24]
        if command == 0x19:
            vm, length, offset, filesize = struct.unpack_from("<QQQQ", data, cursor + 24)
            segments.append((vm, filesize, offset))
            if data[cursor+8:cursor+24].split(b"\0")[0]==b"__TEXT":
                preferred=vm
            for index in range(struct.unpack_from("<I", data, cursor + 64)[0]):
                at = cursor + 72 + index * 80
                name, _, address, length, offset = struct.unpack_from("<16s16sQQI", data, at)
                sections[name.rstrip(b"\0").decode()] = (address, length, offset)
        cursor += size
    return segments,sections,uuid,preferred


segments,sections,uuid,preferred=load_image(data)
assert uuid == bytes.fromhex("fbce22c17e1b3e0d9be866ff9291943e" if old else "b49e75781d8635d38bb57daf68fed8a8")


def offset(address):
    for vm, length, file_offset in segments:
        if vm <= address < vm + length:
            return file_offset + address - vm
    raise ValueError(hex(address))


def pointer(address):
    value = struct.unpack_from("<Q", data, offset(address))[0]
    # This UUID uses DYLD_CHAINED_PTR_64_OFFSET rebases.
    assert not value & (1 << 63), "unexpected bound pointer"
    return (value & 0xFFFFFFFFF) + preferred if value else 0


def string(address):
    at = offset(address)
    return data[at:data.index(0, at)].decode()


def methods(address):
    result = {}
    if not address:
        return result
    flags, count = struct.unpack_from("<II", data, offset(address))
    for index in range(count):
        at = address + 8 + index * (flags & 0xFFFF)
        if flags & 0x80000000:
            name, types, imp = struct.unpack_from("<iii", data, offset(at))
            name += at
            if not flags & 0x40000000:
                name = pointer(name)
            result[string(name)] = (string(at + 4 + types), at + 8 + imp)
        else:
            result[string(pointer(at))] = (string(pointer(at + 8)), pointer(at + 16))
    return result


def classes_in_image():
    classes = {}
    address, length, _ = sections["__objc_classlist"]
    for index in range(length // 8):
        cls = pointer(address + index * 8)
        ro = pointer(cls + 32) & ~7
        classes[string(pointer(ro + 24))] = methods(pointer(ro + 32))
    return classes


classes=classes_in_image()

factory = classes["_TtC37ContextMenu_PlatformLegacyAdapterImpl16PresenterFactory"]
track = ("contextMenuPresenterForTrackWithTrackURI:trackName:trackMetadata:playable:imageURL:"
         "artists:albumName:albumURI:viewURI:contextSourceURI:metadataTitle:logContext:options:actions:")
entity = ("contextMenuPresenterForHeaderImageURL:headerImagePlaceholder:imageStyle:title:subtitle:"
          "metadataTitle:actions:entityURL:options:")
assert factory[track] == ("@124@0:8@16@24@32B40@44@52@60@68@76@84@92@100@108@116", 0x10655389C if old else 0x10765a5f8)
assert factory[entity] == ("@88@0:8@16@24q32@40@48@56@64@72@80", 0x103ED4E34 if old else 0x100ee7aa0)
platform = classes["_TtC23Collection_PlatformImpl22CollectionPlatformImpl"]
assert platform["stateProvider"] == ("@16@0:8", 0x1057C8BD8 if old else 0x10604e86c)
assert platform["addURL:showUIConfirmation:completion:"] == ("v36@0:8@16B24@?28", 0x1058E29D4 if old else 0x1013c8148)
assert classes["SPTShowEntityContextMenuAction"]["performAction"] == ("@16@0:8", 0x1041971FC if old else 0x106d16924)
# Independently recorded disassembly: the addURL completion's Swift-to-block
# bridge forwards a single BOOL (not an object/error or a guessed wire schema).
for address, instruction in ({
    0x108B403B4: 0x1797E663,  # b 0x107139d40
    0x107139D40: 0xF9400A81,  # ldr x1, [x20, #16]
    0x107139D44: 0x16B31F32,  # b 0x101e01a0c
    0x101E01A0C: 0xAA0103E8,  # mov x8, x1
    0x101E01A10: 0xF9400822,  # ldr x2, [x1, #16] (block invoke)
    0x101E01A14: 0x15A15C19,  # b 0x108658a78
    0x108658A78: 0x12000001,  # and w1, w0, #1
    0x108658A7C: 0xAA0803E0,  # mov x0, x8 (block)
    0x108658A80: 0xD61F0040,  # br x2
} if old else {
    0x1062793d8: 0x175b28ff,  # b 0x1039437d4
    0x1039437d4: 0xf9400a88,  # ldr x8,[x20,#16]
    0x1039437d8: 0xf9400902,  # ldr x2,[x8,#16]
    0x1039437dc: 0x12000001,  # and w1,w0,#1
    0x1039437e0: 0xaa0803e0,  # mov x0,x8
    0x1039437e4: 0xd61f0040,  # br x2
}).items():
    assert struct.unpack_from("<I", data, offset(address))[0] == instruction, hex(address)
for cls,selector,encoding in [
    ("SPTOfflineManagerImplementation","initWithScheduler:offlineManager:syncManager:metadataModel:","@48@0:8@16^{OfflineManager=^^?}24^{SyncManager=^^?^^?}32^v40"),
    ("SPTOfflineManagerImplementation","stateForTrackWithURL:","Q24@0:8@16"),
    ("SPTOfflineManagerImplementation","makeEntityAvailableOfflineWithURL:trackURLs:","v32@0:8@16@24"),
    ("SPTOfflineManagerImplementation","makeEntityAvailableOfflineWithURL:","v24@0:8@16"),
    ("SPTOfflineManagerImplementation","resetEntityOfflineAvailabilityWithURL:","v24@0:8@16"),
    ("SPTFreeTierOfflineStatusUpdatingContentOperation","offlineSyncStatusForURL:","q24@0:8@16"),
    ("SPTEsperantoTransportBridgeImpl","callSingle:method:payload:onResponse:","@48@0:8@16@24@32@?40"),
    ("SPTEsperantoTransportBridgeImpl","callStream:method:payload:onResponse:","@48@0:8@16@24@32@?40"),
    ("SPTEsperantoCosmosTransport","callSingle:method:payload:onResponse:","@48@0:8@16@24@32@?40"),
    ("SPTEsperantoCosmosTransport","callStream:method:payload:onResponse:","@48@0:8@16@24@32@?40"),
    ("SPTCoreProductState","stringForKey:","@24@0:8@16"),
    ("SPTCoreProductState","setOriginalValues:","v24@0:8@16"),
    ("SPTCoreURLSessionDataDelegate","URLSession:task:didCompleteWithError:","v40@0:8@16@24@32"),
    ("_TtC26Connectivity_HttpClientKit20HttpClientURLSession","URLSession:task:didCompleteWithError:","v40@0:8@16@24@32"),
]:
    assert classes[cls][selector][0]==encoding,(version,cls,selector)
with ZipFile(ipa) as archive:
    data=archive.read("Payload/Spotify.app/Frameworks/SpotifyShared.framework/SpotifyShared")
segments,sections,uuid,preferred=load_image(data)
assert uuid==bytes.fromhex("2e074234cfc63f0e9255c9881824167a" if old else "30bac55f8361373aad607f0535395641")
assert classes_in_image()["SPTDataLoaderService"]["URLSession:task:didCompleteWithError:"][0]=="v40@0:8@16@24@32"
print(f"PASS: {version} fingerprint, track/entity/action, native manager and transport ABIs; BOOL completion bridge")
