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

## After the probes

The plan is the Android port's, step for step:

* an iOS analogue of `0009-premake-android-target.patch` (all dependencies
  static, one executable in the bundle instead of a `SharedLib` for a Java
  activity),
* an analogue of `0010-android-paths.patch`: the bundle is read-only, and
  `$HOME` is the app container,
* the touch layer and `mods/sfostouch` from the Sailfish port,
* the game data downloaded on first start, as on Android,
* and `pyrogenesis -mod=mod` as the smoke test, because the mod-selection
  screen needs a few MB instead of 3.5 GB.

Unanswered either way: multiplayer, sound (iOS has no OpenAL to speak of), and
how a JIT-less SpiderMonkey holds up in a real match.
