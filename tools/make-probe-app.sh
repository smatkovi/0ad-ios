#!/bin/sh
# Wrap one executable into a .app bundle the simulator will install.
#
#   tools/make-probe-app.sh <prefix> <quelle.c> <bundle-id> <ausgabe.app>
#
# No Xcode project: a bundle is a directory with an Info.plist and a binary.
# The ad-hoc signature ("-") is enough for the simulator -- it refuses an
# unsigned bundle but does not care who signed it.
set -e

PREFIX=${1:?prefix}
SOURCE=${2:?quelle}
BUNDLE_ID=${3:?bundle-id}
APP=${4:?ausgabe.app}
MIN=${MIN:-13.0}
NAME=$(basename "$APP" .app)

SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
CFLAGS=$(pkg-config --cflags sdl2)
# sdl2.pc names only -lSDL2. On iOS the actual main() lives in SDL2main
# (src/main/uikit/SDL_uikit_main.c): it sets up the UIApplication and then
# calls SDL_main, which is what SDL.h has renamed our main() to. Without it
# the link fails with an undefined _main and nothing else to go on.
LIBS="-lSDL2main $(pkg-config --static --libs sdl2)"
# GLES is deprecated on iOS since 12.0 and every single call says so.
CFLAGS="$CFLAGS -DGLES_SILENCE_DEPRECATION" 

rm -rf "$APP"
mkdir -p "$APP"

# shellcheck disable=SC2086
xcrun --sdk iphonesimulator clang \
    -target arm64-apple-ios$MIN-simulator \
    -isysroot "$SDK_PATH" \
    -O2 -Wall -Wextra \
    $CFLAGS -o "$APP/$NAME" "$SOURCE" $LIBS

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>$NAME</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleName</key><string>$NAME</string>
	<key>CFBundleDisplayName</key><string>$NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
	<key>MinimumOSVersion</key><string>$MIN</string>
	<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
	<key>UILaunchScreen</key><dict/>
	<key>UIRequiresFullScreen</key><true/>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$APP"
echo "gebaut: $APP"
sh "$(dirname "$0")/show-platform.sh" "$APP/$NAME"
