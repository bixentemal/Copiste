# Copiste

Turn an image on your clipboard into text, on demand, entirely on device.

Copy a screenshot of a command, a code block from a video call, or a page of a book, then:

| Shortcut | What happens |
| --- | --- |
| `⌥⌘O` | The text is typed into whatever app you are in. Your image stays on the clipboard. |
| `⌥⌘⇧O` | The text replaces the clipboard, ready for a normal `⌘V` whenever you like. |

Both shortcuts are configurable. Nothing runs in the background — Copiste does no work at all
until you press one.

## Layout, not just characters

Recognition returns the words and where they sit, but throws away every bit of whitespace.
Copiste rebuilds it from the geometry, so indented text comes back indented:

```
┌─────────────────────────┐
│ Deploy checklist        │     Deploy checklist
│                         │
│ • Run the test suite    │  →  • Run the test suite
│ • Tag the release       │     • Tag the release
│     - use vMAJOR.MINOR  │         - use vMAJOR.MINOR
└─────────────────────────┘
```

- Lines are ordered top to bottom, and fragments sharing a visual line merge left to right.
- Horizontal offsets become leading spaces, measured against the character width of the
  recognized text itself, so indentation survives at any font size or resolution.
- Vertical gaps wider than the usual line pitch become blank lines, restoring paragraphs.
- Near-equal indents snap to a shared level, so measurement wobble cannot stagger a list.

Recognition uses Apple's Vision framework — the engine behind Live Text. Nothing leaves your
Mac, there is no API key, and it works offline.

## Install

Download the latest `Copiste-<version>.zip` from
[Releases](https://github.com/bixentemal/Copiste/releases/latest), unzip it, and move
`Copiste.app` to `/Applications`.

The build is **not notarized** — that needs a paid Apple Developer ID, which this project
does not have — so macOS quarantines it and reports it as damaged until you clear the flag
yourself. Install it only if you are comfortable with that:

```sh
xattr -dr com.apple.quarantine /Applications/Copiste.app
```

Open it; the icon appears in the menu bar. Then press `⌥⌘O` once and grant Accessibility
permission when macOS asks (see below). Requires macOS 15 or later.

### Build from source instead

You need macOS 15 or later and Swift 6.2 (install Xcode, or the Swift toolchain).

```sh
git clone <this repo> && cd copiste
./Scripts/setup_signing.sh        # once — see "Signing", below
./Scripts/compile_and_run.sh      # builds, tests, packages, and launches Copiste.app
```

The icon appears in the menu bar. To keep it, move `Copiste.app` to `/Applications` and open
it from there.

### Granting Accessibility permission

`⌥⌘O` pastes by sending a `⌘V` keystroke to another app, and macOS only lets an app do that
with **Accessibility** permission. The first time you press `⌥⌘O`, macOS asks; approve it in
System Settings → Privacy & Security → Accessibility.

`⌥⌘⇧O` needs no permission at all — it only writes to the clipboard. If you would rather not
grant anything, use that shortcut and paste with `⌘V` yourself.

### Signing, and why the permission keeps breaking without it

macOS remembers "this app may control your computer" against the app's *identity*. For an
ad-hoc signed app, that identity is **the hash of the binary** — so every rebuild produces a
different app as far as macOS is concerned, and the permission silently stops applying.
System Settings still shows Copiste with its toggle on, which makes it look like the app is
broken when in fact it is a different app wearing the same name.

`./Scripts/setup_signing.sh` fixes this permanently. It creates a self-signed code-signing
certificate in its own keychain — no `sudo`, nothing trusted system-wide, nothing that can
sign anything but your local builds — and `package_app.sh` uses it automatically. The app's
identity becomes its bundle id plus that certificate, which does not change when you
rebuild, so the permission survives. You approve it once after running the script and then
never again. To undo it entirely:

```sh
security delete-keychain copiste-dev.keychain
rm -f ~/.copiste-dev-signing
```

### If pasting stops working

Make macOS forget its answer, so it asks again the next time you press `⌥⌘O`:

```sh
tccutil reset Accessibility com.bixentemal.copiste.debug   # a build from compile_and_run.sh
tccutil reset Accessibility com.bixentemal.copiste         # a build from package_app.sh release
```

`tccutil` ships with macOS. `reset Accessibility <bundle id>` removes that one app's entry
from the permission database — Copiste's row disappears from System Settings and the prompt
comes back. It affects nothing else. Debug and release builds have different bundle ids, so
reset whichever one you are running; resetting an id you have never granted is harmless and
reports "No such bundle identifier".

### Updating

Releases are signed with the same certificate, so macOS treats an update as the same app and
your Accessibility permission carries over. (An ad-hoc signed build would not: its identity
is the code hash, so every update would ask again.)

## What it accepts

Image data on the clipboard (PNG, TIFF, JPEG), or an image file copied in Finder
(`png jpg jpeg tiff tif heic gif bmp`).

When there is nothing to work with, the menu items are greyed out and a shortcut press
reports why on the status line in the menu. The menu-bar icon also flashes after every
action, so a shortcut pressed with the menu closed is never silent.

## Build

```sh
swift build                        # dev build
swift test                         # 35 tests
./Scripts/compile_and_run.sh       # kill, build, test, package, relaunch
./Scripts/package_app.sh release   # Copiste.app, ad-hoc signed
./Scripts/make_icons.sh            # regenerate icons from Artwork/copiste-logo.png
./Scripts/setup_signing.sh         # once: stable signing identity (see above)
./Scripts/release.sh               # build + verify a release artifact
./Scripts/release.sh --publish     # ...and publish it to GitHub
swiftformat . && swiftlint lint
```

Requires macOS 15+ and Swift 6.2. One dependency:
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).

## Design

`docs/SPEC.md` is the specification the app was built from: the behaviour, the layout
algorithm in detail, the architecture, and a decision log explaining why each choice was
made — including what was deliberately left out.

## License

MIT. See `LICENSE`.
