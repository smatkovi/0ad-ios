#!/bin/sh
# Pack a .app into an .ipa for sideloading.
#
#   tools/make-ipa.sh <buendel.app> <ausgabe.ipa>
#
# An .ipa is a zip with the bundle inside a directory called Payload, and that is
# the whole format. It is not signed here: Sideloadly, AltStore and Xcode all
# re-sign what they install, with the certificate of whoever is installing it, so
# a signature from the build would only be thrown away. (An Apple developer
# account signs for a year, a free one for seven days.)
set -e

APP=${1:?buendel.app}
IPA=${2:?ausgabe.ipa}

case "$APP" in *.app) ;; *) echo "kein .app: $APP" >&2; exit 1;; esac
[ -d "$APP" ] || { echo "nicht da: $APP" >&2; exit 1; }
grep -q iPhoneOS "$APP/Info.plist" || \
    echo "Warnung: das Buendel ist keines fuer ein Geraet (PLATFORM=iphoneos)" >&2

# zip is run from inside the payload directory, so the path has to be absolute.
case "$IPA" in /*) OUT=$IPA ;; *) OUT=$PWD/$IPA ;; esac

WORK=$(dirname "$OUT")/.ipa-payload
rm -rf "$WORK"
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"

rm -f "$OUT"
# -y keeps symlinks as symlinks; a bundle should not grow when it is packed.
(cd "$WORK" && zip -qry "$OUT" Payload)
rm -rf "$WORK"

ls -lh "$OUT"
unzip -l "$OUT" | head -8
