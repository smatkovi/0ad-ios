#!/bin/sh
# Fetch and patch the 0 A.D. source tree.
#
#   tools/get-source.sh [verzeichnis]      default: ext/0ad-0.28.0
#
# The patch stack, in order:
#
#   0001         guards the gloox include so --without-lobby works
#   0002 0003    make the --gles path usable
#   0005 - 0008  touch input and gestures (SDL_GetNumTouchDevices, so they
#                switch themselves on wherever there is a touchscreen)
#   0007         build only the release SpiderMonkey, not debug as well
#   0014         glMapBuffer does not exist on OpenGL ES
#   0015 - 0017  this port: premake's --ios, OS_IOS, the data path
#
# 0001-0008 come from the Sailfish port and 0014 from the Android one, copied
# rather than referenced so this tree builds on its own.
set -e

HERE=$(cd "$(dirname "$0")/.." && pwd)
DEST=${1:-$HERE/ext}
VER=${VER:-0.28.0}
SRC="$DEST/0ad-$VER"

mkdir -p "$DEST"
cd "$DEST"

[ -e "0ad-$VER-unix-build.tar.xz" ] || \
    curl -fL -o "0ad-$VER-unix-build.tar.xz" \
        "https://releases.wildfiregames.com/0ad-$VER-unix-build.tar.xz"

if [ ! -d "$SRC" ]; then
    tar xf "0ad-$VER-unix-build.tar.xz"
    for p in "$HERE"/patches/0*.patch; do
        if out=$(cd "$SRC" && patch -p0 -N -r - --dry-run < "$p" 2>&1); then
            (cd "$SRC" && patch -p0 -N -r - < "$p" > /dev/null)
            echo "angewandt: $(basename "$p")"
        else
            printf '%s\n' "$out"
            echo "Patch scheitert: $p"
            exit 1
        fi
    done
fi

echo "$SRC"
