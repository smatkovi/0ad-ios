#!/bin/sh
# Build SpiderMonkey 128 for iOS -- the question the whole port hangs on.
#
#   tools/build-mozjs-ios.sh iphonesimulator /tmp/prefix-sim
#   tools/build-mozjs-ios.sh iphoneos        /tmp/prefix-dev
#
# The Android port did not have to answer this: Termux ships mozjs 128 for
# aarch64, at exactly the version 0 A.D. 0.28 wants. For iOS nobody packages
# it, so it gets built from the tarball 0 A.D. bundles in its own source
# release (mozjs-128.13.0.tar.xz), with 0 A.D.'s patches applied -- the same
# source the engine is tested against, not a fresh Firefox checkout.
#
# Two things are different from every other platform:
#
#   * The target triple. Mozilla's build system does know iOS (it canonicalises
#     "ios-sim" to clang's "ios-simulator" and finds the iphonesimulator SDK
#     through xcrun on its own), so --target=aarch64-apple-ios-sim is a real
#     target and not a hack.
#   * No JIT. iOS gives no app the right to make memory executable, so
#     SpiderMonkey has to run as an interpreter. The simulator would let a JIT
#     through, but then the two builds would diverge in exactly the part that
#     is hardest to debug, so both get --disable-jit.
#
# Only the release build is made. 0 A.D.'s own build.sh builds debug as well,
# which doubles the time for something no port needs.
set -e

SDK=${1:-iphonesimulator}
PREFIX=${2:?usage: build-mozjs-ios.sh <iphonesimulator|iphoneos> <prefix>}
PV=${PV:-128.13.0}
ZEROAD=${ZEROAD:-0.28.0}
MIN=${MIN:-13.0}
W=${W:-$PWD/ext}
JOBS=${JOBS:-}

case "$SDK" in
    iphonesimulator) TRIPLE=aarch64-apple-ios-sim ;;
    iphoneos)        TRIPLE=aarch64-apple-ios ;;
    *) echo "unknown SDK: $SDK"; exit 1 ;;
esac

# Built before, and cached? 0 A.D.'s own build.sh keeps the same kind of stamp
# for the same reason: this is four to five minutes of every CI run, and the
# dependency cache restores lib/ and include-release/ but not the source tree,
# so without the stamp it is rebuilt from scratch every single time.
if [ "$(cat "$PREFIX/.already-built" 2>/dev/null)" = "$PV+ios-$SDK" ] \
   && [ -e "$PREFIX/lib/libmozjs128-release.a" ]; then
    echo "SpiderMonkey $PV ($SDK): schon gebaut"
    exit 0
fi

mkdir -p "$W"
cd "$W"

# 0 A.D.'s source release carries the SpiderMonkey tarball and the patches.
if [ ! -d "spidermonkey-$ZEROAD" ]; then
    [ -e "0ad-$ZEROAD-unix-build.tar.xz" ] || \
        curl -fL -o "0ad-$ZEROAD-unix-build.tar.xz" \
            "https://releases.wildfiregames.com/0ad-$ZEROAD-unix-build.tar.xz"
    rm -rf unpack && mkdir unpack
    tar xf "0ad-$ZEROAD-unix-build.tar.xz" -C unpack \
        "0ad-$ZEROAD/libraries/source/spidermonkey"
    mv "unpack/0ad-$ZEROAD/libraries/source/spidermonkey" "spidermonkey-$ZEROAD"
    rm -rf unpack
fi

cd "spidermonkey-$ZEROAD"
FOLDER="mozjs-$PV"

if [ ! -d "$FOLDER" ]; then
    # Same exclude list as 0 A.D.'s build.sh: the test suites are a third of
    # the tarball and nothing links against them.
    tar xfJ "$FOLDER.tar.xz" \
        --exclude=js/src/tests/non262 \
        --exclude=js/src/tests/test262 \
        --exclude=js/src/jit-test \
        --exclude=python/mozperftest \
        --exclude=testing/web-platform \
        --exclude=third_party/rust/mp4parse/link-u-avif-sample-images
    ( cd "$FOLDER" && . ../patches/patch.sh )
fi

rustup target add "$TRIPLE"

# cbindgen generates the C headers for the Rust parts and runs on the *host*.
# mach would fetch it itself through `mach bootstrap`, but that is exactly what
# MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE=none forbids, so configure stops with
# "Cannot find cbindgen" -- nothing to do with iOS.
command -v cbindgen > /dev/null || cargo install cbindgen --locked

cd "$FOLDER"
export MOZ_NOSPAM=1
export CFLAGS="$CFLAGS -w"
export CXXFLAGS="$CXXFLAGS -w"
export MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE=none
export MOZBUILD_STATE_PATH="$PWD/mozbuild-state"

# Deliberately only three options on top of 0 A.D.'s own mozconfig (which
# already has --enable-project=js, --disable-jemalloc, --without-intl-api,
# --disable-js-shell and --disable-tests): the target, the iOS deployment
# version, and no JIT.
#
# --disable-shared-js was in here once and cost a link failure: the static
# library then references _moz_set_max_dirty_page_modifier, which nothing
# defines with jemalloc switched off. 0 A.D.'s macOS build keeps shared-js on
# and links js_static.a anyway, so this build does the same.
OPTIONS="--target=$TRIPLE
    --enable-ios-target=$MIN
    --disable-jit
    --enable-optimize"

# SpiderMonkey bundles a zlib and links it into js_static.a. 0 A.D.'s own
# build.sh passes --with-system-zlib on Darwin for that reason; without it the
# engine link ends in five duplicate symbols (adler32_z, crc32_z, ...) between
# libmozjs128-release.a and our own libz.a. Only when a PKG_CONFIG_LIBDIR is
# given, so that it cannot pick up the host's zlib by accident -- the probe
# workflow runs this script without one and keeps the bundled copy.
if [ -n "$PKG_CONFIG_LIBDIR" ] && pkg-config --exists zlib 2>/dev/null; then
    OPTIONS="$OPTIONS
    --with-system-zlib"
fi

echo "--- configure/build: $TRIPLE"
set -x
MOZCONFIG="$(pwd)/../mozconfig" \
MOZCONFIG_OPTIONS="$OPTIONS" \
BUILD_DIR="build-release" \
    ./mach build $JOBS
set +x

# What came out, and for which platform. A wrong platform links fine and only
# shows up when the simulator refuses the app.
# 0 A.D.'s own build.sh greps the jsrust path out of backend.mk, which came
# out empty here; searching for the file is shorter and does not depend on how
# the generated makefile is worded.
LIB=$(find build-release -name libjs_static.a | head -1)
RUST_LIB=$(find build-release -name libjsrust.a | head -1)
[ -n "$LIB" ] && [ -n "$RUST_LIB" ] || {
    echo "Bibliotheken nicht gefunden:"
    find build-release -name "*.a" | head -20
    exit 1
}
# The names and the layout are 0 A.D.'s own bundled-SpiderMonkey layout, so
# pointing PREFIX at libraries/source/spidermonkey makes premake's non-system
# path find everything with no --with-system-mozjs and no .pc file at all.
mkdir -p "$PREFIX/lib" "$PREFIX/include-release"
cp -L "$LIB" "$PREFIX/lib/libmozjs128-release.a"
cp -L "$RUST_LIB" "$PREFIX/lib/libmozjs128-rust.a"
cp -R -L build-release/dist/include/* "$PREFIX/include-release/"

# SpiderMonkey copies its own zlib headers into dist/include, and those rename
# every zlib entry point to MOZ_Z_*. The engine then includes that zlib.h
# instead of the real one and the link ends in undefined MOZ_Z_compress,
# MOZ_Z_uncompress, MOZ_Z_compressBound. 0 A.D.'s own build.sh removes exactly
# these three -- but only in its Windows branch (bug #776126).
rm -f "$PREFIX/include-release/mozzconf.h" \
      "$PREFIX/include-release/zconf.h" \
      "$PREFIX/include-release/zlib.h"

# The SDK belongs in the stamp: a device build and a simulator build are not
# interchangeable, and they land in the same place.
echo "$PV+ios-$SDK" > "$PREFIX/.already-built"

echo "--- Ergebnis:"
ls -la "$PREFIX/lib"
lipo -info "$PREFIX/lib/libmozjs128-release.a" || true
