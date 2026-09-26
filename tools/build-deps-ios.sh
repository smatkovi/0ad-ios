#!/bin/sh
# Build every dependency pyrogenesis needs, for iOS or the iOS Simulator.
#
#   tools/build-deps-ios.sh [iphonesimulator|iphoneos] [quellbaum]
#
# Two scripts do the work:
#
#   libraries/build-macos-libs.sh   0 A.D.'s own, with the iOS mode from
#                                   patch 0018. Installs into libraries/macos
#                                   and collects every .pc file in
#                                   libraries/macos/pkgconfig, which is exactly
#                                   where premake's macosx branch looks.
#   tools/build-mozjs-ios.sh        SpiderMonkey 128, into
#                                   libraries/source/spidermonkey, in the layout
#                                   the bundled (non---with-system-mozjs) path
#                                   expects.
#
# Afterwards every .pc premake will ask for is checked, because a failed
# pkg-config lookup is silent in premake: the library disappears from the link
# line and the build fails much later with thousands of undefined symbols.
set -e

SDK=${1:-iphonesimulator}
HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC=${2:-$HERE/ext/0ad-0.28.0}
JOBS=${JOBS:--j3}

# When a configure scripts gives up, the reason is in its config.log and nowhere
# else -- and the log sits several directories deep in a tree that CI throws
# away. So say it here, on failure, while the tree still exists.
show_config_log()
{
    log=$(find "$SRC/libraries/macos" -name config.log -newermt "-30 minutes" \
          2>/dev/null | head -1)
    [ -n "$log" ] || return 0
    echo "### $log (die letzten Versuche)"
    grep -nE "^configure:[0-9]+: (checking|error|failed)|^configure: error" "$log" | tail -25
    echo "### und die letzten 40 Zeilen"
    tail -40 "$log"
}

echo "### Abhängigkeiten für $SDK"
if ! ( cd "$SRC/libraries" && IOS_SDK="$SDK" sh ./build-macos-libs.sh "$JOBS" ); then
    show_config_log
    exit 1
fi

echo "### SpiderMonkey"
sh "$HERE/tools/build-mozjs-ios.sh" "$SDK" "$SRC/libraries/source/spidermonkey"

echo "### Was da ist"
PC="$SRC/libraries/macos/pkgconfig"
ls "$PC" || true
missing=
for pc in sdl2 libxml-2.0 zlib libcurl icu-i18n icu-uc libsodium libpng fmt \
          freetype2 libenet; do
    PKG_CONFIG_LIBDIR="$PC" pkg-config --exists "$pc" 2>/dev/null || \
        missing="$missing $pc"
done
ls -la "$SRC/libraries/macos/boost/include/boost/version.hpp" 2>/dev/null || \
    missing="$missing boost-headers"
ls -la "$SRC/libraries/source/spidermonkey/lib" 2>/dev/null || \
    missing="$missing spidermonkey"

if [ -n "$missing" ]; then
    echo "FEHLT:$missing"
    exit 1
fi
echo "alle da"
