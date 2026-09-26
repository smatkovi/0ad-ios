#!/bin/sh
# Print what platform a Mach-O file was built for.
#
#   tools/show-platform.sh <datei>...
#
# arm64 for the device and arm64 for the simulator are the same architecture --
# the only thing that tells them apart is the platform in LC_BUILD_VERSION
# (IOS vs IOSSIMULATOR). Mixing them links fine and only shows up much later,
# when `simctl install` refuses the bundle or the device rejects the app.
#
# vtool reads executables and dylibs; for a static archive it gives up, so
# otool's load commands are the fallback (platform 2 = IOS, 7 = IOSSIMULATOR).
for f in "$@"; do
    printf '%s: ' "$f"
    out=$(vtool -show-build-version "$f" 2>/dev/null |
          awk '/platform/ { print $2; exit }')
    if [ -z "$out" ]; then
        out=$(otool -l "$f" 2>/dev/null |
              awk '/LC_BUILD_VERSION/ { found = 1 }
                   found && /platform/ { print $2; exit }')
        case "$out" in
            2) out="IOS (2)" ;;
            7) out="IOSSIMULATOR (7)" ;;
        esac
    fi
    echo "${out:-unbekannt}"
done
