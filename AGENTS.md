# Tempus — working notes for Codex

You are working in a native iOS app. **Read `CLAUDE.md` first; it is binding.** `DESIGN.md`
before any UI work, `SETUP.md` for the extension targets. This file only adds what those
documents assume an agent already knows: how to drive the build, the simulator and the
reference from a shell. Everything here was learned the expensive way — trust it over guesses.

## Ground rules (the short list)

- Design tokens only (`TColor`, `TFont`, `TSpace`, `TRadius`, `TDur`, `Animation.glide`).
  No raw hex, no magic spacing, no springs.
- **Minimal diffs.** Reuse what is in `DesignSystem/` before writing anything. Do not refactor
  around the change, do not add abstractions, do not "clean up" neighbours.
- **Never commit, push, tag or archive unless the task says so.** Leave the tree for review.
- **Done means built and walked**: `xcodebuild` passes for the `Tempus` scheme (which builds
  all five extensions) *and* you drove the affected flow in the simulator and looked at it.
  Build 17 compiled, archived and passed its self-checks with every page dead — a build is
  not verification.
- Verify on the **iPhone 17 Pro simulator only**. Do not create other simulators.
- The reference (`source_of_truth.html`) wins on every screen, number, string and timing,
  except the rows in CLAUDE.md's divergence table — those are answers, not findings.
- When something you were asked to fix does not reproduce, say so with the evidence
  (frames, logs). Do not report a fix you could not see.

## Build

```bash
xcodebuild -project Tempus.xcodeproj -scheme Tempus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -30
# zsh: the pipeline's status is ${pipestatus[1]}, not $?
# one extension alone (needs -sdk iphonesimulator or it wants a device profile):
xcodebuild -project Tempus.xcodeproj -target TempusMonitor -sdk iphonesimulator build
```

Xcode's own error output is what matters; SourceKit "only available in macOS" diagnostics on
the extension sources are editor noise.

The built app lands under `~/Library/Developer/Xcode/DerivedData/Tempus-*/Build/Products/Debug-iphonesimulator/Tempus.app`.

## Simulator

**If you are sandboxed, say so and stop at the edit.** `xcrun simctl … CoreSimulatorService
connection became invalid / Connection refused` and `xcodebuild … ModuleCache: Operation not
permitted` mean the Codex seatbelt is on: no build and no simulator are possible from inside it.
Make the code change, report the files and what to verify, and leave the build and the walk to
whoever launched you. Do not claim the build passed.

**Always use the UDID, never `booted`** — more than one simulator is often booted and
`booted` silently picks the wrong one.

```bash
UDID=$(xcrun simctl list devices | grep 'iPhone 17 Pro (' | grep -o '[0-9A-F-]\{36\}' | head -1)
xcrun simctl boot $UDID 2>/dev/null; open -a Simulator
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Tempus-*/Build/Products/Debug-iphonesimulator/Tempus.app | head -1)
xcrun simctl install $UDID "$APP"
xcrun simctl terminate $UDID com.crescerestudios.tempus 2>/dev/null
xcrun simctl launch --console-pty $UDID com.crescerestudios.tempus -tempusPhase status > /tmp/tempus-codex/app.log 2>&1 &
```

- **Launch seams** (`-tempusPhase …`, `-tempusStep …`, `-tempusPerm`, `-tempusCardClose`, …)
  are the way to reach a screen or play a set-piece without taps. The full table is in
  CLAUDE.md under *Launch seams*; `Tempus/Models/LaunchSeams.swift` is the code.
- **Read the app's stdout** (`--console-pty` into a file). A line reading
  `AttributeGraph: cycle detected` at launch means the router is dead for the life of the
  process — read for it before debugging anything that "does not respond". A DEBUG self-check
  assert traps the app at launch; its message names the failing check.
- A temporary `print()` in a `body` or in `AppModel.go()` is the fastest way to see what
  SwiftUI actually sees. Remove it by editing the exact line, never by deleting every line that
  contains the marker.

### Screenshots and pixels

```bash
xcrun simctl io $UDID screenshot /tmp/tempus-codex/shot.png   # 1206×2622 = 402×874 @3x
```

Measure with Python + Pillow (installed): sample pixels, fit edges, compare against the
reference's numbers. A screenshot is evidence; "it looks right" is not.

### Tapping

`xcrun simctl` cannot tap. `/opt/homebrew/bin/cliclick` sends real macOS events the
Simulator window accepts:

```bash
osascript -e 'tell application "System Events" to tell process "Simulator" to get {position, size} of window 1'
screencapture -x -R<x>,<y>,<w>,<h> /tmp/tempus-codex/win.png   # 2x retina: screen pt = origin + px/2
cliclick c:<x>,<y>
```

Read the target's pixel off the window capture, convert, then click. **Leave ~2.5 s between
taps** — rapid clicks swallow each other and look like a bug that is not there. Bring the
Simulator window to the front first (`open -a Simulator`).

### Recording an animation (the only way to judge one)

```bash
xcrun simctl io $UDID recordVideo --codec h264 --force /tmp/tempus-codex/take.mp4 &
REC=$!; sleep 1
xcrun simctl launch $UDID com.crescerestudios.tempus -tempusPhase status -tempusPerm
sleep 8; kill -INT $REC; sleep 2
mkdir -p /tmp/tempus-codex/frames
ffmpeg -y -i /tmp/tempus-codex/take.mp4 -vf fps=30 /tmp/tempus-codex/frames/f%04d.png
```

Then read the frames with Pillow: a per-frame luminance timeline of a region tells a fade from
a cut, a blank frame from a cross-fade, and a 1250 ms rise from a 700 ms one. A cut and a fade
are one line apart in the source and unmistakable on the timeline — **never sign off an
animation from the source code alone.**

### What the simulator cannot show

- **Live Activities / the Dynamic Island** — the sim shows none. Reason from the code, say
  it is unverified, and ask for a device check.
- **`DeviceActivityReport` views** (`TempusReport`) — blank in the sim; the flight log's
  screen-time cards only fill on a phone with Screen Time connected.
- **World tracking, the accelerometer, Face ID** — each has a documented fallback path.
- `AuthorizationCenter` reports Screen Time as approved in the sim regardless.

## The reference

Unpack it with the Python snippet in CLAUDE.md (`/tmp/tempus-ref/`; `app.jsx` is the
365 KB file). **Execute it, don't only read it**: `carrier.js` is written in layers and only
running it under `node` (shim `global.window = global`) tells you what it actually does.

For CSS animations, the keyframes and durations are in `app.jsx`'s `<style>` block
(`tp-permin`, `tp-permdown`, …); the router's transition table maps a transition name to its
in/out classes and its teardown timeout. If you can drive a browser, serve the repo
(`python3 -m http.server 8000`) and freeze an animation with
`document.getAnimations().forEach(a => { a.pause(); a.currentTime = 600 })` to measure a
mid-frame; React's teardown fires on a `setTimeout`, so patch `window.setTimeout` to stretch
it if you need the outgoing layer to stay. If you cannot drive a browser, measure the Swift
side on frames and compare against the keyframe arithmetic.

## Things that read as if they would work and do not

CLAUDE.md's *Architecture notes* has the full list with the reasoning. The ones that bite most:

- CSS `opacity` on a parent → SwiftUI needs `.compositingGroup()` before `.opacity`.
- `.clipShape` goes **before** `.offset`/`.scaleEffect`, never after.
- `TSafeArea.insets` may be read inside a `Shape`'s `path(in:)`, never in a `body`.
- `save()` coalesces; `saveNow()` is synchronous. Do not encode on a transition's first frame.
- A `.animation(_:value:).delay()` second stage does not run; sequence from its own flag after
  a real `Task.sleep`.
- CSS `box-shadow` spread folds into alpha via `TShadow.ShadowLayer.css(...)`, never into blur.
- `Text(timerInterval:)` lays out at its widest possible string; size its slot explicitly.
- The report extension's Info.plist must **not** declare `NSExtensionPrincipalClass`.
- Adding an `@Environment` object to a screen means adding it to `ScreenWarm.render` too, or
  the app crashes 2.4 s after launch.
- New shared files for an extension go in that target's membership exception on the `Tempus`
  group in `project.pbxproj`; never copy the file.

## Signing and delivery

Archives sign **manually** with the App Store profiles named in SETUP.md; "no devices" from
Xcode does not mean plug a phone in. Upload goes through Xcode Organizer — there are no App
Store Connect CLI credentials on this machine. Do not go looking for them.

## Reporting back

Work in `/tmp/tempus-codex/` for scratch files. Report: what changed (files, one line each),
the build result verbatim if it failed, what you drove in the simulator and the screenshot or
frame paths that show it, and anything you could not verify and why.
