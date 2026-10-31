#!/bin/bash
set -eo pipefail

. ../../include/path.sh

if [[ "$1" != build ]]; then
    echo 'Only clean CI builds are supported.' >&2
    exit 1
fi
test "$(git rev-parse HEAD)" = "$NUVIO_LIBASS_COMMIT"
git apply --reverse --check "$NUVIO_NATIVE_DIR/libass-exact-edges.patch"

export CPPFLAGS="${CPPFLAGS:-} -DASS_EVENT_THREADS"
./autogen.sh
mkdir -p "_build$ndk_suffix"
cd "_build$ndk_suffix"
asm_args=(--enable-asm)
if [[ "$ndk_triple" == arm-* ]]; then asm_args=(); fi
../configure --host="$ndk_triple" --with-pic "${asm_args[@]}" \
    --enable-static --disable-shared --enable-libunibreak \
    --disable-require-system-font-provider
make -j"$cores"
make DESTDIR="$prefix_dir" install
