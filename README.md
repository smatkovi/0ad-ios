# 0 A.D. 0.28.0 for iOS

Companion to [0ad-android](https://github.com/smatkovi/0ad-android) and
[0ad-sailfish](https://github.com/smatkovi/0ad-sailfish): the same engine, the
same version, the same OpenGL ES path and the same touch layer — only the
platform below it changes.

**Status: it runs in the simulator, with sound; there is an unsigned `.ipa` for
a phone that nobody has installed yet.** The two probes that started this are
below for the record; they answered the questions that decided the shape of the
port:

| | answer |
| --- | --- |
| OpenGL ES in the simulator | **yes** — `GL_VERSION=OpenGL ES 2.0 APPLE-21.0.27`, the middle pixel came back `255,153,0`, exactly the triangle's colour. `GL_RENDERER=Apple Software Renderer`, so the simulator renders GLES **in software**: right pixels, no statement about speed. |
| SpiderMonkey 128 for `aarch64-apple-ios-sim` | **yes** — "Your build was successful!" in four minutes, `libjs_static.a` and `libjsrust.a`, both stamped IOSSIMULATOR, built `--disable-jit`. |

Two things got in the way, neither of them about iOS: `sdl2.pc` names only
`-lSDL2` while the real `main()` lives in `SDL2main` (an undefined `_main` and
nothing else to go on), and `configure` stopped on a missing **cbindgen**,
which `mach` would normally fetch itself — `MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE=none`
forbids that. One line each.

A third cost half an hour of runner time: `simctl launch --console-pty`
attached to a pipe instead of a terminal never returns.

## Why this is not simply the Android port again

The Android port stands on one lucky fact: **Termux packages every dependency
for aarch64 already**, SpiderMonkey 128 included, at exactly the version
0 A.D. 0.28 wants. `tools/make-sysroot.py` downloads `.deb`s and unpacks them,
and days of cross-compiling turn into a 90-second download.

For iOS there is nobody to download from. Every library has to be built
against the iOS SDK, and the one that decides the project is SpiderMonkey.

The other difference is smaller than it looks: NSR Reader could not use the
iOS Simulator at all, because the Qt for iOS package from aqtinstall ships its
static plugin initialisers built for the device only, so the simulator link
fails on the platform plugin itself. **0 A.D. has no Qt.** SDL2 and every
dependency are built here from source, so they can be built for the simulator
SDK like anything else.

## The two probes

`.github/workflows/probe.yml`, two independent jobs on a `macos-14` runner.

### 1. Does the simulator render OpenGL ES?

`probe/triangle.c` — SDL2, a GLES2 context, one orange triangle, and then
`glReadPixels` on the middle pixel. The result goes to `Documents/probe.txt`
in the app container, which CI reads back with `simctl get_app_container`; the
screenshot is only for looking at. A screenshot alone cannot tell "renders"
from "black", which is exactly the failure worth catching.

That NSR Reader runs in the simulator says Metal works there, through Qt. It
says nothing about Apple's OpenGL-ES-over-Metal path on a headless arm64 VM,
and 0 A.D. has no Metal backend.

### 2. Does SpiderMonkey 128 build for `aarch64-apple-ios-sim`?

`tools/build-mozjs-ios.sh` — from the `mozjs-128.13.0.tar.xz` that 0 A.D.
bundles in its own source release, with 0 A.D.'s patches, so it is the source
the engine is tested against.

Two things are known before the first run:

* **Mozilla's build system does know iOS.** `build/moz.configure/init.configure`
  canonicalises `ios-sim` to clang's `ios-simulator`, defines `XP_IOS`, and
  `--with-ios-sdk` finds the `iphonesimulator` SDK through `xcrun` by itself.
  So `--target=aarch64-apple-ios-sim` is a real target, not a hack.
* **There will be no JIT.** iOS grants no app the right to make memory
  executable, so SpiderMonkey runs as an interpreter. The simulator would let
  a JIT through, but then the two builds would differ in the hardest part to
  debug, so both get `--disable-jit`. 0 A.D.'s simulation is JS-heavy; this
  will cost speed, and how much is an open question.

If probe 2 fails at `configure`, that is a build-system project of its own and
not a port — the point of asking now is to find out before touching premake.

## The patches

`tools/get-source.sh` fetches the 0 A.D. source release and applies the stack;
all twenty-four apply cleanly and in order. The table is the first eleven -- the
ones that came before there was an iOS build at all; everything from 0018 on is
described where it belongs in the sections below.

| | |
| --- | --- |
| 0001 | guards the gloox include so `--without-lobby` works |
| 0002 0003 | make the `--gles` path usable |
| 0005 - 0008 | touch input and gestures. They ask `SDL_GetNumTouchDevices()` instead of naming a platform, so they switch themselves on here — nothing iOS-specific was needed |
| 0007 | build only the release SpiderMonkey |
| 0014 | `glMapBuffer` does not exist on OpenGL ES |
| **0015** | premake's `--ios` |
| **0016** | `OS_IOS`, and the three frameworks that are desktop-only |
| **0017** | where the game data is when it was downloaded |

0001-0008 come from the Sailfish port and 0014 from the Android one, copied
rather than referenced so this tree builds on its own.

**iOS is Darwin**, so `--ios` is not a new platform but a set of exceptions to
the macosx target: `premake5 --os=macosx --ios`. The dylib naming, `-framework`
linking, `lib/sysdep/os/osx` and the bundle layout are already right. What is
left is small:

* the architecture cannot be probed (`cc -dumpmachine` answers for the host),
* `ApplicationServices` and `Cocoa` are the desktop; iOS has `Foundation` and
  `UIKit`. The engine never calls ApplicationServices — the include in
  `osx.cpp` is a leftover — and Cocoa only came in for Atlas,
* `CoreServices`, which FCollada links "for a few utility functions", is not a
  linkable framework on iOS; what it uses lives in CoreFoundation,
* `FSEvents` does not exist, so directory watching does nothing,
* `AppKit` in `osx_atlas.mm`: Atlas is a wxWidgets editor in a second process,
  which iOS has no concept of.

What did **not** need patching is the more interesting half: `extern_libs5.lua`
is untouched. SDL2 and mozjs go through pkg-config like everywhere else; there
is no `opengl` entry at all in 0.28, because glad resolves GL entry points at
runtime through `SDL_GL_GetProcAddress`, so no GLES framework has to be named;
iconv is in the SDK; and the writable directories already come from Foundation,
which means `~/Library/Application Support/0ad` lands inside the app container
by itself. The only real gap was data *in* the bundle — it is read-only and
signed, so 3.5 GB cannot go there, the same reason Android downloads it on
first start.

Checked so far: `premake5 --os=macosx --ios --gles …` generates the whole
project (on Linux, no Mac needed), and the link line comes out with
`-framework CoreFoundation -framework Foundation -framework UIKit` and no trace
of Cocoa or ApplicationServices.

## It runs

**0 A.D. starts, loads the whole game and draws on iOS** -- full screen, upright
and legible. The simulator shows the first-launch dialog, "Thank you for
installing 0 A.D. Empires Ascendant!", over the main menu artwork, with its
buttons where they belong: the GUI, the fonts, the textures and the GUI's
JavaScript on a SpiderMonkey without a JIT, all of it working.

    frame 1: window 852x393, drawable 852x393, viewport 852x393,
             middle pixel 87,86,87

**And it has sound.** openal-soft's CoreAudio backend opens a device in the
headless simulator, which was the one thing about the audio that could not be
settled from any source:

    Sound Card     : CoreAudio Default;
    Sound Drivers  : 1.1 ALSOFT 1.24.2

It drew sideways in a corner at first, and the reason was not the one that
looked obvious. The simulator *does* rotate the app to landscape -- it simply
captures in the device's native portrait. What put the picture in the corner was
a unit mismatch of the port's own making: the engine takes its backbuffer from
`SDL_GL_GetDrawableSize` and its viewport from `SDL_GetWindowSize`, pixels
against points, and `SDL_WINDOW_ALLOW_HIGHDPI` made those differ by three. One
ninth of the frame, at the origin. Measured off the screenshot: the whole
interface inside a 393x853 block of a 1179x2556 capture.

The last three things in the way were each invisible from the outside, and each
took measuring rather than guessing:

| | |
| --- | --- |
| The frame loop ran inside a run-loop timer callback and re-entered the run loop from there. `SDL_main` now hands the frame to UIKit and returns | 0023 |
| The window asked to be resizable and not fullscreen, and never asked for ALLOW_HIGHDPI. On iOS a window *is* the screen | 0027 |
| **The backbuffer is not framebuffer zero.** A CAEAGLLayer is fed through a framebuffer object SDL makes with the context; binding zero is legal and draws nowhere, silently, at full speed | 0028 |

The last one is the one to remember. The engine says so itself --
"Backbuffer for GL is a special case with a zero framebuffer" -- and it is true
everywhere except here. It cost eleven runs, most of them spent on instruments
that lied: `simctl spawn ps` finds no ps inside the runtime, `ps -p` printed a
bare header for a live pid, and the stdout of an app started with `simctl
launch` goes nowhere at all. What settled it was writing the evidence into a
file in the app container and reading the buffer back after a bare clear:
black, with GL_INVALID_ENUM.

## Does it play?

The menu is not the game. A match is where the JavaScript gets real work -- the
map is *generated* in JS, Petra decides for two players, the simulation steps --
and where terrain and unit meshes go through Apple's software GLES instead of a
few hundred GUI quads. So the smoke test has a third arm, `Play a match`: the
same bundle as the first one, started with

    -autostart=random/mainland -autostart-size=128 -autostart-players=2
    -autostart-ai=1:petra -autostart-ai=2:petra -autostart-victory=endless

128 tiles instead of the default 192, because generating the map and drawing it
both cost by area. It waits for the first turn -- up to fifteen minutes, since
what map generation costs here is one of the things being measured -- then lets
the match run three minutes longer, and gates on two separate claims: **a turn
was reached**, and **the turn number is still rising**. A screenshot of terrain
would only ever prove the first frame.

What makes that readable is patch 0030. The frame note now carries a clock and
the turn number, and fires every ten seconds as well as every three hundredth
frame. Dividing frames by wall time was the only rate this port had so far, and
only for a run that ended exactly when the screenshots did.

**And it plays.** The first turn arrives **27 seconds** after launch -- that is
`random/mainland` at 128 tiles, generated in JavaScript on a SpiderMonkey without
a JIT -- and four minutes later it is still going:

    frame  137 at  27387 ms: ... middle pixel  0, 0, 0, turn 1
    frame  951 at 196004 ms: ... middle pixel 76,68,59, turn 703
    frame 1500 at 276058 ms: ... middle pixel 77,69,60, turn 1101

`mainlog.html` says what they were doing, too. Animations are loaded when a unit
first needs one, so `carry_meat`, `gather_fruit`, `walk_pickaxe` and
`attack_ranged_hip` are gatherers gathering and archers shooting -- not a map
standing still.

**The rate is not one number, and the reason is worth more than the number.** The
arm has run twice on the same commit, same seeds, same match:

| | frames/s | turns/s | first turn |
| --- | --- | --- | --- |
| run 1 | 5.48 | 4.42 | 27 s |
| run 2 | 2.86 | 2.85 | 25 s |

A factor of two between two runs of the same code -- that is the runner, and it
is why the honest figure here is a range. But look at the second column against
the first, and the engine says exactly why:

    // At the normal sim rate, we currently want to render at least one
    // frame per simulation turn, so let maxTurns be 1.
    size_t maxTurns = (size_t)m_SimRate;                    // ps/Game.cpp:433

**At most one simulation turn per drawn frame, by design.** So the simulation
rate is `min(5, frames per second)` -- five because a turn is 200 ms -- and both
runs land on it: run 1 draws fast enough for the 5/s ceiling to bind (4.42 after
overhead), run 2 is frame-bound and comes out at exactly one turn per frame.

Which settles what is actually slow here, and it is **not** the JavaScript. The
benchmark below replays a whole match without a JIT at sixty turns a second on
this class of machine; the simulation has an order of magnitude of headroom. What
sets the pace in the simulator is Apple's software renderer.

The screenshot after those four minutes is a Ptolemaic game at 31/40 population,
with farms, trees, sheep, and both players' territory on the minimap. The only
crash report in the arm is `XPC_EXIT_REASON_SIGTERM_TIMEOUT`, which is what
`simctl shutdown` does to a game inside a frame callback.

What none of it settles is the phone. **The simulator runs the same arm64 code on
the Mac's own CPU**: the JavaScript here is as fast as the host and only the
graphics are software. A phone reverses both sides of that.

## On a phone

Nothing in this port has ever run on an iPhone -- but the build for one exists
and came out right on its first attempt: **a 25 MB unsigned `.ipa`**, every slice
in it stamped IOS rather than IOSSIMULATOR, the dependencies for `iphoneos`
included. What it does differently is worth writing down.

**The bundle carries no game data.** `tools/make-app.sh <quellbaum> - <ziel.app>`
leaves it out and puts a manifest in instead; `tools/make-ipa.sh` wraps the
result in the `Payload/` directory that makes an `.ipa`. Nothing is signed:
Sideloadly, AltStore and Xcode all re-sign what they install, so a signature from
the build would only be thrown away. An Apple developer account is good for a
year, a free account for seven days.

**The data is fetched on first start** (patch 0029), the way aria2c would do it
if aria2c could run here -- it cannot, because iOS starts no child processes,
which is also why there is no unzip and no tar on the phone. So: 8 MB chunks, six
range requests at a time through NSURLSession, each written straight into its
offset of a file truncated to its final size, one character of state per chunk so
an interrupted download continues, and SHA-256 over the finished file before the
directory is renamed from `data.part` to the `data` that `Paths::RootData()`
looks for.

It is 3.5 GB, not the 1.4 GB the upstream release weighs: that number is the
tar.xz, and xz packs the game's zips by two and a half to one. Undoing that on
the phone would need an xz decoder and a tar reader, so what travels is the zips
themselves -- `public.zip`, `mod.zip` and the few kB of `config/`, republished as
release assets by `tools/make-data-release.sh`. A release asset may not exceed
2 GiB and `public.zip` is 3.5 GB, so it comes in parts of 1792 MiB, which is 224
chunks: a part has to begin and end on a chunk boundary, or a chunk would have to
be fetched from two parts at once.

The download is the one thing here that cannot be tried on the platform it is
for. It is tried at a different size instead: the simulator build also runs with
no data in the bundle and a manifest that cuts the 89 MB base mod into twelve
parts, which is the same arithmetic and the same return into `RunGameOrAtlas`.
That run works end to end --

    download: 89 MB to fetch, 22897 MB free
    download: ranges: yes, six at a time
    download: mods/mod/mod.zip: complete and verified
    download: data complete in .../Application Support/0ad/data

-- and the screen that follows is the mod selection, drawn from a file that was
not in the bundle four minutes earlier.

What a phone should do better than the simulator, for once: real GLES 3.x
hardware instead of Apple's software renderer (patch 0024 does not even apply
there), and a rotation that needs no explaining.

And what pins it to **iOS 17.4**: `BrowserEngineCore` (patch 0021). SpiderMonkey's
jit directory references Apple's W^X interface even when built `--disable-jit`,
and that framework is not older than 17.4. Two stub symbols would lift it back
to 13.0, since nothing ever calls them without a JIT.

## The dependencies, and the engine

**`pyrogenesis` builds and links for the iOS Simulator**: 71 MB, arm64, stamped
IOSSIMULATOR. `.github/workflows/build.yml` does it end to end on a `macos-14`
runner, from the source tarball to the binary.

There is no Termux here, so every dependency is built against the SDK - but not
by a new script: 0 A.D. ships `libraries/build-macos-libs.sh`, which already
downloads, patches, configures and installs all of them for macOS and collects
the `.pc` files in `libraries/macos/pkgconfig`, exactly where premake's macosx
branch looks. Patch 0018 gives it an `IOS_SDK` mode.

Built: zlib, libcurl, libiconv, libxml2, SDL2 (with the uikit backend), Boost
(headers), libpng, freetype, ICU, ENet, libsodium, fmt, and SpiderMonkey 128.
Skipped by name: wxWidgets (Atlas), gmp/nettle/gnutls/gloox (lobby),
miniupnpc, MoltenVK, FCollada and NVTT. The sound -- libogg, libvorbis,
openal-soft with its CoreAudio backend -- was on that list until it turned out
that nothing but `--without-audio` was keeping it off.

### What actually went wrong, in order

Not one of these was "iOS cannot do this". Every single one was a tool seeing
the wrong flags, or a header path pointing somewhere else:

| | |
| --- | --- |
| curl: "We can't compile without socket() support!" | `-isysroot` was missing from `CPPFLAGS`, and a good number of configure tests run the preprocessor alone. "socket can be linked: yes", "socket is prototyped: no" |
| libpng | three configure calls *replace* `CPPFLAGS` instead of appending |
| SDL2 | CMake 4 refuses the 2022 CMakeLists; 2.32.8 instead |
| ICU, first pass | the native build got the iOS flags and could not be executed |
| ICU, second pass | `pkgdata` calls `system()`, unavailable on iOS; the target needs no tools |
| FCollada | wants Carbon's `MPCriticalRegionID`; the Collada module is left out |
| premake | was being built with the iOS wrappers - a host tool |
| `enet/enet.h` not found | the lobby stub's `extern_libs` never named enet; only noticed where enet is not in a default include path |
| `_moz_set_max_dirty_page_modifier` | our `--disable-shared-js` deviated from 0 A.D.'s mozconfig |
| `_main` | SDL2main, the same trap as the GLES probe |
| `be_memory_inline_jit_restrict_rwx_*` | BrowserEngineCore, Apple's W^X interface since iOS 17.4 |
| `iterator_buffer::flush()` | **a real bug in 0 A.D.**: the fmt fallback in `StringBuilder.h` includes `core.h`, the definition is in `format.h` |
| duplicate zlib symbols | SpiderMonkey bundles its own zlib; `--with-system-zlib` |
| `MOZ_Z_compress` | SpiderMonkey's `zlib.h` renames everything to `MOZ_Z_*`; 0 A.D. removes those headers - in its Windows branch only |

Two of these are worth sending upstream: the `StringBuilder.h` include and the
missing `enet` in the lobby stub's library list.

## What the missing JIT costs: 4.6x

Measured rather than guessed, and on macOS, where the question can be asked at
all: `.github/workflows/bench.yml` records one match and replays it against two
SpiderMonkeys that differ in nothing but `--disable-jit`.

    Wiederholung: 19533 Runden
    jit:    70 s, Endzustand df5d2b12b1fc033dd1e3a4728259a0b9
    nojit: 319 s, Endzustand df5d2b12b1fc033dd1e3a4728259a0b9
    jit2:   71 s, Endzustand df5d2b12b1fc033dd1e3a4728259a0b9
    Verhaeltnis: 4.56x   (Rauschen zwischen den beiden JIT-Laeufen: 1.01x)

The fixture is an hour of game time -- 19533 turns out of a sixty-second headless
recording, two Petras on `random/mainland`, victory condition `endless` so the
length is decided by the script and not by how the match goes. The third run is
the noise control: the same jit binary a second time, one percent apart, which is
what makes 4.56 a measurement rather than a sample.

An earlier run of the same benchmark died after printing its first two numbers
and gave **3.30x** on a shorter fixture -- 17133 turns of the *same* match, from
a slower runner recording fewer turns in its sixty seconds. The ratio grows with
the fixture, which makes sense: later turns carry more units, and more units is
more Petra, which is more JavaScript.

Either way the absolute numbers say something the ratio hides. Sixty-five minutes
of game time replays in 319 seconds without a JIT -- **sixty turns a second**,
twelve times faster than the match is played. That is the headroom the iOS
simulator's 3-to-5 turns a second is not using.

The hash is what makes the two times comparable: both runs computed the same
match. The benchmark refuses to report without it, and it refuses just as hard if
the two binaries hash the same -- premake's gmake generator lists only sibling
projects as link dependencies, and mozjs arrives as an external `-l`, so swapping
the library and running make relinks *nothing*. Both arms would have run the same
executable and every ratio would have come out 1.00, green. The binary is deleted
before each link for that reason. For good measure the nojit tier carries **0
vixl symbols** against 2775 in the other, so `--disable-jit` demonstrably arrived.

It took five runs to produce the number, and not one of them failed over the JIT:
an unreachable `gmplib.org` in a dependency this build does not link
(`--without-lobby`, now in `SKIP_LIBS`); a missing `cbindgen`, which 0 A.D.'s own
SpiderMonkey script forbids mach to fetch; a cached `.already-built` stamp for
cxxtest *without* the directory it is about, which `mocks_real` compiles against;
`-autostart="random/arcadia"`, a map that does not exist -- arcadia is a
scenario, and the guard three lines above it was checking a variable the command
never used; and finally the noise control itself, which copied a binary named
`pyrogenesis-jit2` that no stage had ever linked.

## Next

An iPhone. Everything about the device build is checked statically -- that not
one simulator slice is in the link, that the plist says iPhoneOS -- and nothing
about it is checked by running it.

**Is it audible?** A device opens, which is not the same as samples reaching it,
and a simulator cannot be listened to -- `simctl io recordVideo` records no audio.
So a fourth arm asks openal-soft to write what it mixes into a file instead of
handing it to CoreAudio (`drivers = wave`, the config handed over through
`SIMCTL_CHILD_ALSOFT_CONF`). Same engine calls, same decoders, same mixer; only
the last hop differs, and the RIFF header is never finalised because the app is
killed, so the check reads the raw samples past every possible header rather than
trusting a length field. What it cannot answer is whether a speaker moves.

Unanswered either way: multiplayer (no classic Bluetooth, and UDP broadcast
discovery needs Apple's multicast entitlement), and whether an interface designed
for a mouse can be worked with fingers -- the match above does not touch the touch
patches, because nothing injects touches into a simulator.

Collada stays out (patch 0020): it is a second shared library loaded at runtime,
which an `.ipa` cannot carry, and it only matters for loading *unbaked* meshes --
the released data has none.
