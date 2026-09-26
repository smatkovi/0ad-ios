# 0 A.D. 0.28.0 for iOS

Companion to [0ad-android](https://github.com/smatkovi/0ad-android) and
[0ad-sailfish](https://github.com/smatkovi/0ad-sailfish): the same engine, the
same version, the same OpenGL ES path and the same touch layer — only the
platform below it changes.

**Status: both probes are green.** Nothing is ported yet, but the two
questions that decide the shape of the port are answered:

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
all eleven apply cleanly and in order.

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

**0 A.D. starts, loads the whole game and draws on iOS.** The simulator shows
its first-launch dialog -- "Thank you for installing 0 A.D. Empires Ascendant!"
-- over the main menu artwork: the GUI, the fonts, the textures and the GUI's
JavaScript on a SpiderMonkey without a JIT, all of it working.

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
ogg/vorbis/openal (sound), miniupnpc, MoltenVK, FCollada and NVTT.

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

## Next

The `.app` bundle and `pyrogenesis -mod=mod` in the simulator - the mod
selection screen needs a few MB instead of 3.5 GB, which makes it the right
first thing to look at.

Unanswered either way: multiplayer, sound (iOS has no OpenAL to speak of), and
how a JIT-less SpiderMonkey holds up in a real match.
