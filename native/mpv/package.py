import hashlib
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import urllib.request
import zipfile


root = pathlib.Path(__file__).resolve().parents[2]
pins = json.loads((root / "native/mpv/pins.json").read_text())
destination = root / "native-output/mpv-android-lib-nuviotv.aar"
base = root / "native-output/mpv-android-lib-0.1.12.aar"
urllib.request.urlretrieve(pins["base_aar_url"], base)
if hashlib.sha256(base.read_bytes()).hexdigest() != pins["base_aar_sha256"]:
    sys.exit("Base AAR checksum does not match the pinned Maven artifact")

abis = ("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
replacements = {f"jni/{abi}/libmpv.so": root / f"native-output/{abi}/libmpv.so" for abi in abis}


def needed(path):
    dynamic = subprocess.check_output(["readelf", "--dynamic", str(path)], text=True)
    return set(re.findall(r"\(NEEDED\).*\[(.*?)\]", dynamic))


def symbols(path, undefined):
    table = subprocess.check_output(["readelf", "--wide", "--dyn-syms", str(path)], text=True)
    names = set()
    for line in table.splitlines():
        columns = line.split()
        if len(columns) >= 8 and columns[0].endswith(":") and columns[0][:-1].isdigit():
            if (columns[6] == "UND") == undefined:
                names.add(columns[7].split("@")[0])
    return names


with zipfile.ZipFile(base) as original, tempfile.TemporaryDirectory() as temporary:
    for abi in abis:
        directory = pathlib.Path(temporary) / abi
        directory.mkdir()
        exports = set()
        for entry in original.infolist():
            if entry.filename.startswith(f"jni/{abi}/") and entry.filename.endswith(".so"):
                library = directory / pathlib.PurePosixPath(entry.filename).name
                library.write_bytes(original.read(entry))
                exports.update(symbols(library, undefined=False))
        stock = directory / "libmpv.so"
        candidate = replacements[f"jni/{abi}/libmpv.so"]
        if needed(stock) != needed(candidate):
            sys.exit(f"Native dependency set changed: {abi}")
        old_api = {symbol for symbol in symbols(stock, False) if symbol.startswith("mpv_")}
        new_api = {symbol for symbol in symbols(candidate, False) if symbol.startswith("mpv_")}
        if old_api != new_api:
            sys.exit(f"mpv client API exports changed: {abi}")
        new_cpp = {symbol for symbol in symbols(candidate, True) if symbol.startswith("_Z")}
        missing = new_cpp - exports
        if missing:
            sys.exit(f"Packaged C++ runtime cannot satisfy {abi}: {sorted(missing)}")

with zipfile.ZipFile(base) as original, zipfile.ZipFile(destination, "w") as output:
    if not replacements.keys() <= set(original.namelist()):
        sys.exit("The base AAR is missing required mpv libraries")
    for entry in original.infolist():
        replacement = replacements.get(entry.filename)
        contents = replacement.read_bytes() if replacement else original.read(entry)
        output.writestr(entry, contents)

with zipfile.ZipFile(base) as original, zipfile.ZipFile(destination) as output:
    if original.namelist() != output.namelist():
        sys.exit("AAR entries changed")
    for name in original.namelist():
        changed = original.read(name) != output.read(name)
        if changed != (name in replacements):
            sys.exit(f"Unexpected AAR difference: {name}")

source_pins = {key: value for key, value in pins.items() if not key.startswith("prebuilt_")}
manifest = {"pins": source_pins, "aar_sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}
(root / "native-output/provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Verified: only four libmpv.so entries changed in {destination.name}")
