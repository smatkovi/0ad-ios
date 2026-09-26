#!/bin/sh
# Build pyrogenesis for iOS or the iOS Simulator.
#
#   tools/ios-build.sh [iphonesimulator|iphoneos] [quellbaum]
#
# premake is run with `--os=macosx --ios`: iOS is Darwin, so the macosx
# branches are the right ones, and --ios (patch 0015) only changes the handful
# of places where the desktop and the phone differ.
#
# The compiler is a wrapper rather than a pile of flags on the make line,
# because premake bakes CC/CXX into the generated makefiles and also runs
# probe compiles of its own -- the same reason the Android port uses wrappers.
# The wrapper carries the three things that make a compiler an iOS compiler:
#
#   -target arm64-apple-ios<min>[-simulator]   what separates device from
#                                              simulator; both are arm64
#   -isysroot <sdk>                            the SDK
#   -DGLES_SILENCE_DEPRECATION                 GLES is deprecated since iOS 12
#                                              and says so at every call
#
# Dependencies are expected where premake's macosx branch looks for them:
# libraries/macos, with the .pc files collected in libraries/macos/pkgconfig.
# That is where 0 A.D.'s own build-macos-libs.sh puts them.
set -e

SDK=${1:-iphonesimulator}
SRC=${2:-$(cd "$(dirname "$0")/.." && pwd)/ext/0ad-0.28.0}
MIN=${MIN:-13.0}
JOBS=${JOBS:-3}

case "$SDK" in
    iphonesimulator) TARGET=arm64-apple-ios$MIN-simulator ;;
    iphoneos)        TARGET=arm64-apple-ios$MIN ;;
    *) echo "unbekanntes SDK: $SDK"; exit 1 ;;
esac

W=${W:-${TMPDIR:-/tmp}/0ad-ios-build}
mkdir -p "$W/ccwrap"

if command -v xcrun > /dev/null; then
    SDKPATH=$(xcrun --sdk "$SDK" --show-sdk-path)
    REAL_CC=$(xcrun --sdk "$SDK" -f clang)
    REAL_CXX=$(xcrun --sdk "$SDK" -f clang++)
    REAL_AR=$(xcrun --sdk "$SDK" -f ar)
else
    # No Xcode here: this path exists so premake generation can be checked on
    # a Linux box. Compiling needs a Mac.
    : "${SDKPATH:?ohne xcrun muessen SDKPATH, CC und CXX gesetzt sein}"
    REAL_CC=${CC:?}
    REAL_CXX=${CXX:?}
    REAL_AR=${AR:-ar}
fi

for pair in cc:"$REAL_CC" c++:"$REAL_CXX"; do
    name=${pair%%:*}
    real=${pair#*:}
    cat > "$W/ccwrap/ios-$name" <<WRAP
#!/bin/sh
exec "$real" -target $TARGET -isysroot "$SDKPATH" -DGLES_SILENCE_DEPRECATION "\$@"
WRAP
    chmod +x "$W/ccwrap/ios-$name"
done

# premake is a *host* tool: build it before the wrappers are in the
# environment, or it comes out as an iOS binary that cannot run on the machine
# that is supposed to run it.
PREMAKE="$SRC/libraries/source/premake-core/bin/premake5"
[ -x "$PREMAKE" ] || ( unset CC CXX AR; sh "$SRC/libraries/source/premake-core/build.sh" )

export CC="$W/ccwrap/ios-cc"
export CXX="$W/ccwrap/ios-c++"
export AR="$REAL_AR"
export HOSTTYPE=aarch64
export PKG_CONFIG_LIBDIR="$SRC/libraries/macos/pkgconfig"

# A pkg-config lookup that fails is **silent** in premake: the library simply
# vanishes from the link line, and what you get instead is a few thousand
# undefined symbols much later. So check first and say which ones are missing.
missing=
for pc in sdl2 libxml-2.0 zlib libcurl icu-i18n icu-uc libsodium libpng fmt \
          freetype2 libenet; do
    pkg-config --exists "$pc" 2>/dev/null || missing="$missing $pc"
done
if [ -n "$missing" ]; then
    echo "FEHLER: pkg-config findet nicht:$missing"
    echo "        gesucht wird in $PKG_CONFIG_LIBDIR"
    echo "        (tools/build-deps-ios.sh baut sie dorthin)"
    exit 1
fi

echo "### premake ($SDK, $TARGET)"
cd "$SRC/build/premake"
rm -rf ../workspaces/ios
"$PREMAKE" --file=premake5.lua --outpath=../workspaces/ios \
    --os=macosx --ios --gles \
    --without-pch --without-lobby --without-atlas --without-tests \
    --without-audio --without-miniupnpc --without-nvtt --without-dap-interface \
    gmake

# The trap the Android port ran into does not apply here, and it is worth a
# note: premake compiles tests/mozdebug.c to find out whether a *system* mozjs
# was built with --enable-debug, and treats any failure as "yes", which then
# collides with js-config.h. This build does not use --with-system-mozjs -- the
# SpiderMonkey libraries go into libraries/source/spidermonkey/lib, where the
# bundled path expects them -- so the probe never runs. (The Debug
# configuration in the generated makefile does define DEBUG; that is the
# bundled path's own doing and only concerns config=debug, which is not built.)

echo "### make"
cd ../workspaces/ios
make -j"$JOBS" config=release pyrogenesis 2>&1 | tee "$W/build.log" | \
    grep -E "^(==== |.*(error|Error):)" || true

echo "### Ergebnis"
ls -la "$SRC/binaries/system/" || true
sh "$(cd "$(dirname "$0")" && pwd)/show-platform.sh" \
    "$SRC/binaries/system/pyrogenesis" 2>/dev/null || true
