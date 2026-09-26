#!/bin/sh
# Fetch the little bit of game data the smoke test needs.
#
#   tools/get-mod-data.sh [zielverzeichnis]    default: ext/smoke-data
#
# 0 A.D.'s *source* release carries only the _test.* mods. The base mod - the
# one with the mod-selection screen, which is what `pyrogenesis -mod=mod` shows -
# lives in the data release, as a single 89 MB mod.zip. That is too big to keep
# in this repository, and the full data release is 1.4 GB, so: download once,
# unpack the two paths that matter, and let CI cache the result.
#
# The 3.5 GB "public" mod, with the actual game, is a different matter - that is
# what patch 0017's downloaded-data directory is for.
set -e

HERE=$(cd "$(dirname "$0")/.." && pwd)
DEST=${1:-$HERE/ext/smoke-data}
VER=${VER:-0.28.0}
ARCHIVE="$HERE/ext/0ad-$VER-unix-data.tar.xz"

if [ -e "$DEST/mods/mod/mod.zip" ]; then
    echo "schon da: $DEST"
    exit 0
fi

mkdir -p "$HERE/ext"
[ -e "$ARCHIVE" ] || \
    curl -fL -o "$ARCHIVE" \
        "https://releases.wildfiregames.com/0ad-$VER-unix-data.tar.xz"

rm -rf "$HERE/ext/unpack-data"
mkdir -p "$HERE/ext/unpack-data"
tar xf "$ARCHIVE" -C "$HERE/ext/unpack-data" \
    "0ad-$VER/binaries/data/config" \
    "0ad-$VER/binaries/data/mods/mod"

mkdir -p "$DEST"
cp -R "$HERE/ext/unpack-data/0ad-$VER/binaries/data/config" "$DEST/"
cp -R "$HERE/ext/unpack-data/0ad-$VER/binaries/data/mods" "$DEST/"
rm -rf "$HERE/ext/unpack-data"

# The archive is 1.4 GB and CI caches only what came out of it.
rm -f "$ARCHIVE"

du -sh "$DEST"
