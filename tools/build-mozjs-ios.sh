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

OPTIONS="--target=$TRIPLE
    --enable-ios-target=$MIN
    --disable-jit
    --enable-optimize
    --disable-shared-js
    --disable-js-shell
    --disable-tests"

echo "--- configure/build: $TRIPLE"
set -x
MOZCONFIG="$(pwd)/../mozconfig" \
MOZCONFIG_OPTIONS="$OPTIONS" \
BUILD_DIR="build-release" \
    ./mach build $JOBS
set +x

# What came out, and for which platform. A wrong platform links fine and only
# shows up when the simulator refuses the app.
LIB="build-release/js/src/build/libjs_static.a"
RUST_LIB="build-release/$(grep jsrust build-release/js/src/build/backend.mk | cut -d / -f 2-)"
mkdir -p "$PREFIX/lib" "$PREFIX/include"
cp -L "$LIB" "$PREFIX/lib/libmozjs128-release.a"
cp -L "$RUST_LIB" "$PREFIX/lib/libmozjs128-rust.a"
cp -R -L build-release/dist/include/* "$PREFIX/include/"

echo "--- Ergebnis:"
ls -la "$PREFIX/lib"
lipo -info "$PREFIX/lib/libmozjs128-release.a" || true
