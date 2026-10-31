#!/bin/bash
set -euo pipefail

export NUVIO_NATIVE_DIR="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$NUVIO_NATIVE_DIR/../.." && pwd)"
source_dir="$root/.native-mpv"
arch="${1:?architecture required}"
case "$arch" in
    arm64) abi=arm64-v8a ;;
    armv7l) abi=armeabi-v7a ;;
    x86|x86_64) abi="$arch" ;;
    *) echo 'Unsupported architecture' >&2; exit 1 ;;
esac
pin() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$NUVIO_NATIVE_DIR/pins.json" "$1"; }
test "$(git -C "$source_dir" rev-parse HEAD)" = "$(pin wrapper_commit)"
export NUVIO_LIBASS_COMMIT="$(pin libass_commit)"

checkout() {
    local name="$1" url="$2" ref="$3"
    git clone --filter=blob:none --no-checkout "$url" "$source_dir/buildscripts/deps/$name"
    git -C "$source_dir/buildscripts/deps/$name" checkout --detach "$ref"
    git -C "$source_dir/buildscripts/deps/$name" submodule update --init --recursive
}
mkdir -p "$source_dir/buildscripts/deps" "$source_dir/buildscripts/sdk/bin"
checkout libass "$(pin libass_repository)" "$NUVIO_LIBASS_COMMIT"
checkout mpv https://github.com/mpv-player/mpv.git "$(pin mpv_commit)"
checkout libplacebo https://github.com/haasn/libplacebo.git "$(pin libplacebo_commit)"
checkout dav1d https://github.com/videolan/dav1d.git "$(pin dav1d_commit)"
checkout ffmpeg https://github.com/FFmpeg/FFmpeg.git "$(pin ffmpeg_ref)"
checkout freetype2 https://github.com/freetype/freetype.git VER-2-14-1
git -C "$source_dir/buildscripts/deps/libass" apply "$NUVIO_NATIVE_DIR/libass-exact-edges.patch"
cp "$NUVIO_NATIVE_DIR/libass.sh" "$source_dir/buildscripts/scripts/libass.sh"
chmod +x "$source_dir"/buildscripts/{buildall.sh,include/*.sh,scripts/*.sh}
ln -s "$ANDROID_HOME" "$source_dir/buildscripts/sdk/android-sdk-linux"
ln -s "$ANDROID_HOME/ndk/$(pin ndk_version)" "$source_dir/buildscripts/sdk/android-ndk-r29"
curl --fail --location --retry 3 \
    "https://raw.githubusercontent.com/FFmpeg/gas-preprocessor/$(pin gas_preprocessor_commit)/gas-preprocessor.pl" \
    -o "$source_dir/buildscripts/sdk/bin/gas-preprocessor.pl"
chmod +x "$source_dir/buildscripts/sdk/bin/gas-preprocessor.pl"

cd "$source_dir/buildscripts"
IN_CI=1 ./include/download-deps.sh
./buildall.sh --arch "$arch" mpv

out="$root/native-output/$abi"
mkdir -p "$out"
llvm="$ANDROID_HOME/ndk/$(pin ndk_version)/toolchains/llvm/prebuilt/linux-x86_64/bin"
cp "prefix/$arch/lib/libmpv.so" "$out/libmpv.so"
"$llvm/llvm-strip" --strip-unneeded "$out/libmpv.so"
"$llvm/llvm-strings" "$out/libmpv.so" > "$out/strings.txt"
grep -qF LIBASS_RENDER_THREADS "$out/strings.txt"
if grep -qF LIBASS_EXPERIMENTAL_EDGES "$out/strings.txt"; then
    echo 'Coarse-edge mode must not be available in this build.' >&2
    exit 1
fi
"$llvm/llvm-readelf" --dynamic "$out/libmpv.so" > "$out/dynamic.txt"
"$llvm/llvm-readelf" --program-headers "$out/libmpv.so" > "$out/segments.txt"
"$llvm/llvm-nm" --dynamic --defined-only "$out/libmpv.so" > "$out/exports.txt"
cp "$NUVIO_NATIVE_DIR/pins.json" "$out/pins.json"
sha256sum "$out/libmpv.so" > "$out/SHA256SUMS"
