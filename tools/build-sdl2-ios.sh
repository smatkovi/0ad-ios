#!/bin/sh
# Build SDL2 for iOS, static, into a prefix.
#
#   tools/build-sdl2-ios.sh iphonesimulator /tmp/prefix-sim
#   tools/build-sdl2-ios.sh iphoneos        /tmp/prefix-dev
#
# Same version as the Android port so the two stay comparable. Static, because
# an iOS app that is not a framework bundle has nowhere sensible to put a
# dylib, and there is no dynamic linker trickery to get wrong this time.
#
# The one thing worth checking afterwards is the platform stamped into the
# objects: arm64 for the simulator and arm64 for the device are the same
# architecture, and the only thing that tells them apart is the LC_BUILD_VERSION
# platform. Get that wrong and the link succeeds while `simctl install` refuses
# the bundle. tools/show-platform.sh prints it.
set -e

SDK=${1:-iphonesimulator}
PREFIX=${2:?usage: build-sdl2-ios.sh <iphonesimulator|iphoneos> <prefix>}
VER=${VER:-2.32.8}
MIN=${MIN:-13.0}
W=${W:-$PWD/ext}

mkdir -p "$W"
cd "$W"
[ -d "SDL2-$VER" ] || {
    curl -sL "https://github.com/libsdl-org/SDL/releases/download/release-$VER/SDL2-$VER.tar.gz" \
        -o sdl.tar.gz
    tar xf sdl.tar.gz && rm sdl.tar.gz
}

case "$SDK" in
    iphonesimulator) TARGET=arm64-apple-ios$MIN-simulator ;;
    iphoneos)        TARGET=arm64-apple-ios$MIN ;;
    *) echo "unknown SDK: $SDK"; exit 1 ;;
esac

rm -rf "sdl-build-$SDK"
mkdir "sdl-build-$SDK"
cd "sdl-build-$SDK"

# CMAKE_OSX_SYSROOT takes the SDK name; the explicit -target keeps the
# simulator/device distinction out of CMake's hands.
cmake "../SDL2-$VER" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SDK" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
    -DCMAKE_C_FLAGS="-target $TARGET" \
    -DCMAKE_CXX_FLAGS="-target $TARGET" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF \
    > cmake.log 2>&1 || { tail -40 cmake.log; exit 1; }

ninja > build.log 2>&1 || { tail -40 build.log; exit 1; }
ninja install > install.log 2>&1 || { tail -20 install.log; exit 1; }

echo "SDL2 $VER ($SDK) -> $PREFIX"
ls -la "$PREFIX/lib" | head
