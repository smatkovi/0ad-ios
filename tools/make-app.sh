#!/bin/sh
# Wrap pyrogenesis into a .app bundle for the simulator.
#
#   tools/make-app.sh <quellbaum> <datenverzeichnis> <ausgabe.app>
#
# A bundle is a directory with an Info.plist and a binary; no Xcode project is
# involved. The game data goes in as `data/`, because on iOS
# osx_GetBundleResourcesPath() is the .app directory itself, and RootData()
# returns <resources>/data (see patch 0017, which puts a downloaded directory
# ahead of it for the real 3.5 GB).
#
# The ad-hoc signature ("-") is enough for the simulator: it refuses an unsigned
# bundle but does not care who signed it.
set -e

SRC=${1:?quellbaum}
DATA=${2:?datenverzeichnis}
APP=${3:?ausgabe.app}
MIN=${MIN:-13.0}
BUNDLE_ID=${BUNDLE_ID:-org.smatkovi.zeroad}

rm -rf "$APP"
mkdir -p "$APP"
cp "$SRC/binaries/system/pyrogenesis" "$APP/pyrogenesis"
cp -R "$DATA" "$APP/data"

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
	<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
	<key>MinimumOSVersion</key><string>$MIN</string>
	<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
	<key>UILaunchScreen</key><dict/>
	<key>UIRequiresFullScreen</key><true/>
	<key>UIStatusBarHidden</key><true/>
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
du -sh "$APP"
