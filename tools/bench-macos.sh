#!/bin/sh
# How much does a SpiderMonkey without a JIT cost?
#
#   tools/bench-macos.sh <quellbaum> <spieldaten> <ausgabeverzeichnis>
#
# On macOS, not on iOS, and deliberately so: this arm needs no bundle, no
# simulator, no watchdog and no patch, and it is the only one that can produce
# the ratio the question asks for. The absolute number on a device comes later;
# what is wanted first is "how much slower, same machine, same match".
#
# The measurement is a recorded game replayed twice -- once against a
# SpiderMonkey built as usual, once against one built with --disable-jit, which
# is what iOS forces. A replay re-runs the whole simulation including Petra (the
# AI's commands go through PushLocalCommand and are never in the file), so this
# is the JavaScript the port actually pays for.
#
# The trap this script exists to avoid: swapping libmozjs128-release.a and
# running make changes NOTHING. premake's gmake generator lists only sibling
# projects as link dependencies; mozjs arrives as an external -l, so make sees
# an up-to-date binary and does not relink. Both arms then run the same
# executable, both ratios come out 1.00, and the run is green. Hence: delete the
# binary before each link, and refuse to report if the two binaries hash the
# same.
set -e

SRC=${1:?quellbaum}
DATA=${2:?spieldaten}
OUT=${3:?ausgabeverzeichnis}
SECONDS_TO_RECORD=${SECONDS_TO_RECORD:-60}
MAP=${MAP:-mainland}
# Nicht JOBS: upstream fuettert damit mach ein ganzes Argument ("-j2"), hier
# waere es eine blanke Zahl fuer make -j.
MAKE_JOBS=${MAKE_JOBS:-3}

mkdir -p "$OUT"
BIN="$SRC/binaries/system/pyrogenesis"
SM="$SRC/libraries/source/spidermonkey"
TIERS="$SRC/bench-tiers"
mkdir -p "$TIERS"

# --- the game data, where a desktop build looks for it ---------------------
# Paths::RootData() is the executable's directory minus two, plus "data".
mkdir -p "$SRC/binaries/data/mods"
# Verlinkt, nicht kopiert: der Laeufer hat 14 GB Platte und public.zip allein
# ist ueber ein Gigabyte.
for mod in mod public; do
    [ -e "$SRC/binaries/data/mods/$mod" ] || ln -s "$DATA/mods/$mod" "$SRC/binaries/data/mods/$mod"
done
[ -d "$SRC/binaries/data/config" ] || cp -R "$DATA/config" "$SRC/binaries/data/"

# Eine falsche Karte soll Sekunden kosten und nicht Stunden: "arcadia" etwa ist
# ein Szenario, keine Zufallskarte -- und genau die stand hier unten, waehrend
# diese Pruefung $MAP geprueft hat. Es gibt kein maps/random/arcadia.json; die
# Aufzeichnung waere nach Stunden Bauzeit an einer Karte gescheitert, die es
# nicht gibt. Die Pruefung und der Aufruf nennen ab jetzt dieselbe Karte.
unzip -l "$DATA/mods/public/public.zip" "maps/random/$MAP.json" 2>/dev/null \
    | grep -q "maps/random/$MAP.json" \
    || { echo "FEHLER: Zufallskarte '$MAP' gibt es nicht in public.zip"; exit 1; }

# --- one project, two libraries -------------------------------------------
echo "### premake (macOS)"
PREMAKE="$SRC/libraries/source/premake-core/bin/premake5"
[ -x "$PREMAKE" ] || sh "$SRC/libraries/source/premake-core/build.sh"
cd "$SRC/build/premake"
rm -rf ../workspaces/gcc
"$PREMAKE" --file=premake5.lua --outpath=../workspaces/gcc \
    --without-pch --without-atlas --without-lobby --without-tests \
    --without-miniupnpc --without-nvtt --without-dap-interface \
    --macosx-version-min=10.15 \
    gmake

build_spidermonkey()
{
    tier=$1
    options=$2
    if [ -e "$TIERS/$tier/libmozjs128-release.a" ]; then
        echo "### SpiderMonkey ($tier): schon gebaut"
        # Was der ungecachte Pfad hinterlaesst, muss auch hier dastehen, sonst
        # findet der naechste Lauf keine Kopfdateien zum Uebersetzen.
        mkdir -p "$SM/lib"
        rm -rf "$SM/include-release"
        cp -R "$TIERS/$tier/include-release" "$SM/include-release"
        return 0
    fi
    echo "### SpiderMonkey ($tier) $options"
    mkdir -p "$TIERS/$tier"
    # PKG_CONFIG_PATH, weil 0 A.D.s eigener SpiderMonkey-Patch pkg-config auf
    # macOS wieder einschaltet und --with-system-zlib es dann wirklich benutzt;
    # die Zielversion wie alles andere in libraries/macos.
    ( cd "$SM" && PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:$SRC/libraries/macos/pkgconfig" \
        MIN_OSX_VERSION=10.15 CONF_OPTS="$options" sh ./build.sh --force-rebuild )
    cp "$SM/lib/libmozjs128-release.a" "$TIERS/$tier/"
    cp "$SM/lib/libmozjs128-rust.a" "$TIERS/$tier/"
    # js-config.h unterscheidet sich doch -- in ENABLE_WASM_SIMD --, aber dessen
    # einzige Stelle in den oeffentlichen Kopfdateien haengt an JS_CODEGEN_X64/
    # X86, die nie in js-config.h landen. Auf arm64 also folgenlos: einmal
    # uebersetzen, zweimal binden. Geprueft wird es unten trotzdem.
    cp -R "$SM/include-release" "$TIERS/$tier/include-release"
}

link_tier()
{
    tier=$1
    cp "$TIERS/$tier/libmozjs128-release.a" "$SM/lib/"
    cp "$TIERS/$tier/libmozjs128-rust.a" "$SM/lib/"
    rm -f "$BIN"                      # or make will not relink at all
    ( cd "$SRC/build/workspaces/gcc" && make -j"$MAKE_JOBS" config=release pyrogenesis > "$OUT/link-$tier.log" 2>&1 ) \
        || { tail -30 "$OUT/link-$tier.log"; echo "Binden ($tier) gescheitert"; exit 1; }
    cp "$BIN" "$TIERS/pyrogenesis-$tier"
    shasum -a 256 "$TIERS/pyrogenesis-$tier" | tee -a "$OUT/binaries.txt"
}

# cbindgen erzeugt die C-Kopfdateien der Rust-Teile und laeuft auf dem Wirt.
# 0 A.D.s build.sh setzt MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE=none, also darf
# mach es nicht selbst holen: configure bleibt sonst an "Cannot find cbindgen"
# stehen -- nach dem Wiederherstellen der Abhaengigkeiten und vor jeder Messung.
# Dieselbe Zeile steht in tools/build-mozjs-ios.sh; in CI ist es ein brew-Fass.
command -v cbindgen > /dev/null || cargo install cbindgen --locked

build_spidermonkey jit ""
build_spidermonkey nojit "--disable-jit"

# Der Programm-Vergleich unten zeigt nur, dass zwei verschiedene Programme
# entstanden sind -- zwei Baeue derselben Stufe waeren auch verschieden. Ob
# --disable-jit angekommen ist, sagt js-config.h: auf arm64 haengt
# ENABLE_WASM_SIMD direkt am JIT.
grep -q 'define ENABLE_WASM_SIMD' "$TIERS/jit/include-release/js-config.h" \
    || { echo "FEHLER: die jit-Stufe wurde ohne JIT gebaut"; exit 1; }
if grep -q 'define ENABLE_WASM_SIMD' "$TIERS/nojit/include-release/js-config.h"; then
    echo "FEHLER: --disable-jit ist nicht angekommen -- die nojit-Stufe hat noch den JIT"
    exit 1
fi
# Zur Untermauerung, nicht als Schranke: ohne JIT wird der arm64-Assembler
# (vixl) gar nicht erst uebersetzt.
{
    ls -l "$TIERS/jit/libmozjs128-release.a" "$TIERS/nojit/libmozjs128-release.a"
    echo "vixl-Symbole jit:   $(nm -g "$TIERS/jit/libmozjs128-release.a"   2>/dev/null | grep -c vixl || true)"
    echo "vixl-Symbole nojit: $(nm -g "$TIERS/nojit/libmozjs128-release.a" 2>/dev/null | grep -c vixl || true)"
} | tee -a "$OUT/binaries.txt"
# Und die Kopfdateien duerfen sich genau in dieser einen Zeile unterscheiden.
diff -r "$TIERS/jit/include-release" "$TIERS/nojit/include-release" \
    | grep -v 'ENABLE_WASM_SIMD' | grep '^[<>]' \
    && { echo "FEHLER: die Kopfdateien unterscheiden sich mehr als erwartet"; exit 1; } || true

# --- beide binden, bevor irgendetwas Zeit kostet -------------------------
link_tier jit
link_tier nojit

A=$(shasum -a 256 "$TIERS/pyrogenesis-jit"   | cut -d' ' -f1)
B=$(shasum -a 256 "$TIERS/pyrogenesis-nojit" | cut -d' ' -f1)
if [ "$A" = "$B" ]; then
    echo "FEHLER: beide Messreihen haetten dasselbe Programm ausgefuehrt."
    echo "        Der Bibliothekstausch hat nicht neu gebunden -- die Zahlen waeren wertlos."
    exit 1
fi
cp "$TIERS/pyrogenesis-jit" "$BIN"   # die Aufzeichnung laeuft mit JIT

# --- a fixture: one recorded match ----------------------------------------
# Kein rm -rf im Heimatverzeichnis: die Aufzeichnung wird ueber ihr Alter
# gefunden, nicht dadurch, dass vorher alles geloescht wurde.
REPLAYS="$HOME/Library/Application Support/0ad/replays"
touch "$OUT/.stamp"
echo "### Aufzeichnung (${SECONDS_TO_RECORD}s)"
# endless: no victory condition ends the game early, so the length of the
# fixture is decided here and not by how the match happens to go.
"$BIN" -autostart="random/$MAP" -autostart-seed=1 -autostart-aiseed=1 \
    -autostart-ai=1:petra -autostart-ai=2:petra \
    -autostart-aidiff=1:3 -autostart-aidiff=2:3 \
    -autostart-victory=endless -autostart-nonvisual \
    > "$OUT/record.log" 2>&1 &
RECORDER=$!
i=0
while [ "$i" -lt "$SECONDS_TO_RECORD" ]; do
    kill -0 "$RECORDER" 2>/dev/null || {
        tail -20 "$OUT/record.log"; echo "Aufzeichnung vorzeitig beendet"; exit 1; }
    sleep 5
    i=$((i + 5))
done
kill "$RECORDER" 2>/dev/null || true
wait "$RECORDER" 2>/dev/null || true

FIXTURE=$(find "$REPLAYS" -name commands.txt -newer "$OUT/.stamp" 2>/dev/null | head -1)
[ -n "$FIXTURE" ] || { echo "keine Aufzeichnung entstanden"; tail -20 "$OUT/record.log"; exit 1; }
# A killed recorder can leave half a turn behind; cut at the last complete one.
LAST_END=$(grep -n '^end$' "$FIXTURE" | tail -1 | cut -d: -f1)
[ -n "$LAST_END" ] || { echo "Aufzeichnung enthaelt keine ganze Runde"; exit 1; }
head -n "$LAST_END" "$FIXTURE" > "$OUT/fixture.txt"
TURNS=$(grep -c '^turn ' "$OUT/fixture.txt" || true)
[ "${TURNS:-0}" -gt 0 ] || { echo "Aufzeichnung enthaelt keine Runde"; tail -20 "$OUT/record.log"; exit 1; }
echo "### Wiederholung: $TURNS Runden"

# --- replay it once per tier ----------------------------------------------
# replay_tier <name> [programm]
#
# Der Name ist die Zeile im Ergebnis, das Programm die gebundene Stufe. Die
# Rauschkontrolle misst dieselbe jit-Stufe ein zweites Mal -- unter eigenem
# Namen, aber es gibt kein Programm namens jit2, und genau daran ist der erste
# Lauf gestorben, der beide Messwerte schon hatte.
replay_tier()
{
    tier=$1
    programm=${2:-$1}
    cp "$TIERS/pyrogenesis-$programm" "$BIN"
    cd "$SRC/binaries/system"
    rm -f profile.txt profile2.jsonp
    START=$(date +%s)
    if ! ./pyrogenesis -replay="$OUT/fixture.txt" > "$OUT/replay-$tier.log" 2>&1; then
        tail -40 "$OUT/replay-$tier.log"
        echo "Wiedergabe ($tier) gescheitert"
        exit 1
    fi
    END=$(date +%s)
    cp profile.txt "$OUT/profile-$tier.txt" 2>/dev/null || true
    SECONDS_TAKEN=$((END - START))
    HASH=$(grep "^# Final state:" "$OUT/replay-$tier.log" | tail -1 | awk '{print $4}')
    [ -n "$HASH" ] || { tail -40 "$OUT/replay-$tier.log"; echo "kein Endzustand ($tier)"; exit 1; }
    echo "$tier $SECONDS_TAKEN $HASH" >> "$OUT/result.txt"
    echo "### $tier: ${SECONDS_TAKEN}s, Endzustand ${HASH:-(keiner)}"
}

: > "$OUT/result.txt"
replay_tier jit
replay_tier nojit
# Noch einmal die erste Stufe: drei Kerne, drei Arbeits-Threads neben dem
# Hauptthread -- ohne eine Wiederholung laesst sich ein Verhaeltnis von 1,15
# nicht von Rauschen unterscheiden.
replay_tier jit2 jit

# --- erst pruefen, dann rechnen -----------------------------------------
HASH_JIT=$(awk '$1=="jit"{print $3}' "$OUT/result.txt")
HASH_NOJIT=$(awk '$1=="nojit"{print $3}' "$OUT/result.txt")
T_JIT=$(awk '$1=="jit"{print $2}' "$OUT/result.txt")
T_NOJIT=$(awk '$1=="nojit"{print $2}' "$OUT/result.txt")
T_JIT2=$(awk '$1=="jit2"{print $2}' "$OUT/result.txt")

if [ -z "$HASH_JIT" ] || [ "$HASH_JIT" != "$HASH_NOJIT" ]; then
    echo "    mit JIT: ${T_JIT}s / ohne JIT: ${T_NOJIT}s"
    echo "FEHLER: die Endzustaende unterscheiden sich ($HASH_JIT vs $HASH_NOJIT)."
    echo "        Dann haben die beiden nicht dieselbe Partie gerechnet -- kein Verhaeltnis."
    exit 1
fi

echo "### Ergebnis ($TURNS Runden)"
echo "    mit JIT:   ${T_JIT}s   (Wiederholung: ${T_JIT2}s)"
echo "    ohne JIT:  ${T_NOJIT}s"
echo "    Endzustand beider Laeufe: $HASH_JIT"
echo "$T_NOJIT $T_JIT $T_JIT2" | awk '{
    printf "    Verhaeltnis: %.2fx", $1/$2
    if ($3 > 0) printf "   (Rauschen zwischen den beiden JIT-Laeufen: %.2fx)", ($3>$2 ? $3/$2 : $2/$3)
    printf "\n"
}'
