#!/bin/sh
# Wrap pyrogenesis into a .app bundle -- for the simulator, or for a phone.
#
#   tools/make-app.sh <quellbaum> <datenverzeichnis|-> <ausgabe.app>
#
#   PLATFORM=iphonesimulator   Vorgabe; iphoneos macht ein Geraetebuendel
#   MANIFEST=<datei>           statt der Daten, wenn diese "-" sind
#   BUNDLE_ID=, MIN=           wie gehabt
#
# A bundle is a directory with an Info.plist and a binary; no Xcode project is
# involved. Game data, if it comes along, goes in as `data/`, because on iOS
# osx_GetBundleResourcesPath() is the .app directory itself, and RootData()
# returns <resources>/data (see patch 0017).
#
# With "-" instead of a data directory the bundle gets no data at all and
# download.manifest instead: the app then fetches the 1.4 GB into its container
# on first start (patch 0029). That is the only sensible shape for a phone, where
# the bundle would otherwise have to be sideloaded whole.
#
# The two platforms differ in three places, and all three matter:
#
#   * CFBundleSupportedPlatforms. The simulator refuses an iPhoneOS bundle and
#     the phone refuses an iPhoneSimulator one, and the binaries differ as well
#     (LC_BUILD_VERSION, see tools/show-platform.sh).
#   * Signing. The simulator wants *a* signature and does not care whose, so an
#     ad-hoc one does. For a phone the signature has to come from whoever
#     installs it -- Sideloadly, AltStore, an Apple developer account -- so
#     nothing is signed here and the .ipa is handed over unsigned.
#   * MinimumOSVersion. On a phone the binary needs BrowserEngineCore, which
#     exists since iOS 17.4 (see patch 0021). Saying so here means an older
#     phone refuses to install it instead of crashing on launch.
set -e

HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC=${1:?quellbaum}
DATA=${2:?datenverzeichnis oder -}
APP=${3:?ausgabe.app}
PLATFORM=${PLATFORM:-iphonesimulator}
BUNDLE_ID=${BUNDLE_ID:-org.smatkovi.zeroad}
MANIFEST=${MANIFEST:-$HERE/data/download.manifest}

case "$PLATFORM" in
    iphonesimulator)
        PLIST_PLATFORM=iPhoneSimulator
        MIN=${MIN:-13.0}
        ;;
    iphoneos)
        PLIST_PLATFORM=iPhoneOS
        MIN=${MIN:-17.4}
        ;;
    *)
        echo "PLATFORM muss iphonesimulator oder iphoneos sein" >&2
        exit 1
        ;;
esac

rm -rf "$APP"
mkdir -p "$APP"
cp "$SRC/binaries/system/pyrogenesis" "$APP/pyrogenesis"

if [ "$DATA" = "-" ]; then
    if [ ! -e "$MANIFEST" ]; then
        echo "FEHLER: ohne Daten braucht das Buendel $MANIFEST" >&2
        echo "        (erzeugt von tools/make-data-release.sh)" >&2
        exit 1
    fi
    cp "$MANIFEST" "$APP/download.manifest"
    echo "ohne Daten; Manifest: $(grep -c '^[^#]' "$APP/download.manifest") Dateien"
else
    cp -R "$DATA" "$APP/data"
fi

# An icon is not required to install a bundle, but a blank square on the home
# screen is a poor reward for an hour of building. The .icns holds the biggest
# version of the logo; sips is on every Mac.
if [ -e "$SRC/build/resources/0ad.icns" ] && command -v sips > /dev/null; then
    sips -s format png "$SRC/build/resources/0ad.icns" --out "$APP/icon-full.png" \
        > /dev/null 2>&1 || cp "$SRC/build/resources/0ad.png" "$APP/icon-full.png"
    sips -z 120 120 "$APP/icon-full.png" --out "$APP/AppIcon60x60@2x.png" > /dev/null
    sips -z 180 180 "$APP/icon-full.png" --out "$APP/AppIcon60x60@3x.png" > /dev/null
    rm -f "$APP/icon-full.png"
    ICONS='	<key>CFBundleIcons</key>
	<dict>
		<key>CFBundlePrimaryIcon</key>
		<dict>
			<key>CFBundleIconFiles</key>
			<array><string>AppIcon60x60</string></array>
		</dict>
	</dict>'
else
    ICONS=""
fi

# Reachable from the Files app: the game writes its log and the frame notes to
# Documents, and on a phone that is the only way to ever read them.
if [ "$PLATFORM" = iphoneos ]; then
    SHARING='	<key>UIFileSharingEnabled</key><true/>
	<key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>'
else
    SHARING=""
fi

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>pyrogenesis</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleName</key><string>0 A.D.</string>
	<key>CFBundleDisplayName</key><string>0 A.D.</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.28.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleSupportedPlatforms</key><array><string>$PLIST_PLATFORM</string></array>
	<key>MinimumOSVersion</key><string>$MIN</string>
	<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
	<key>UILaunchScreen</key><dict/>
	<key>UIRequiresFullScreen</key><true/>
	<key>UIStatusBarHidden</key><true/>
$ICONS
$SHARING
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
PLIST

if [ "$PLATFORM" = iphonesimulator ]; then
    # The simulator refuses an unsigned bundle but does not care who signed it.
    codesign --force --sign - --timestamp=none "$APP"
else
    echo "nicht signiert -- das macht das Werkzeug, das die .ipa installiert"
fi
echo "gebaut: $APP ($PLIST_PLATFORM, mindestens iOS $MIN)"
du -sh "$APP"
