# Copiste — Specification & Design

> Status: **implemented**. Deviations found during construction are noted inline.
> Target: macOS 15+, Swift 6.2, SwiftUI menu-bar app.
> Bundle id: `com.bixentemal.copiste` (`.debug` suffix for debug builds).

---

## 1. What Copiste is

A macOS menu-bar utility that turns **an image on the clipboard into text**, on demand,
entirely on device.

Two shortcuts, one pipeline:

| Shortcut | Action | Result |
| --- | --- | --- |
| `⌥⌘O` | **Paste Text from Image** | Recognized text is typed into the frontmost app; the image stays on the clipboard afterwards. |
| `⌥⌘⇧O` | **Copy Text from Image** | Recognized text replaces the clipboard, ready for a normal `⌘V` later. |

Both shortcuts are user-configurable. Neither runs any background work: **nothing happens
until you invoke an action.** There is no clipboard watcher, no event tap, no polling.

### Design principle

Copiste is a *pull-based* tool. Every line of code exists on the path between a keypress
and a result. Anything that would require observing the system continuously is out of scope.

---

## 2. Goals / non-goals

**Goals**

- Recognize text in a clipboard image with Apple's Vision framework — offline, no API key,
  no network.
- Reconstruct the *layout* of the recognized text (indentation, paragraph breaks, reading
  order), not just the characters, so a screenshot of code or a nested list pastes back
  usable.
- Two delivery modes (paste / copy) behind configurable global shortcuts.
- Stay small enough to read in one sitting: ~600 lines across 8 source files, one dependency.

**Non-goals**

- Clipboard history, clipboard monitoring, or any transformation of *text* already on the
  clipboard.
- Screen capture. Copiste reads the clipboard; taking the screenshot is `⌘⇧4`'s job.
- Translation, summarization, or any cloud/LLM post-processing of the recognized text.
- Auto-update infrastructure (no signing key → no appcast).
- A CLI target.

---

## 3. User-facing behaviour

### 3.1 Accepted input

An action reads `NSPasteboard.general` and accepts, in order of preference:

1. **Image data** on the pasteboard: `public.png`, `public.tiff`, `public.jpeg`.
2. **An image file reference** (`public.file-url`) whose extension is one of
   `png jpg jpeg tiff tif heic gif bmp` — i.e. a file copied in Finder. The file is read
   from disk at invocation time.

If neither is present, the action is a no-op with a failure signal (§3.4).

### 3.2 `⌥⌘O` — Paste Text from Image

1. Read the image (§3.1). Abort if none.
2. Verify Accessibility permission (§3.5). Abort with a permission message if missing.
3. Recognize text (§4). Abort if the result is empty.
4. Write the text to the pasteboard as `public.utf8-plain-text`.
5. Synthesize `⌘V` to the frontmost app.
6. After **200 ms**, restore the pasteboard to the original image data (and its original
   UTI). The copy the user made survives the operation.

### 3.3 `⌥⌘⇧O` — Copy Text from Image

Steps 1, 3, 4 above, then stop. The clipboard now holds the text and nothing is restored —
that is the point of the action. **Requires no Accessibility permission**, so it remains
available as a fallback when permission is not granted.

### 3.4 Feedback

Copiste is invisible while you work, so every action reports its outcome twice:

- **Menu-bar icon**, for when the menu is closed: dims to ~45 % opacity for 1 s on success;
  switches to a slashed variant for 1 s on failure. Driven by an observable `status` the
  `MenuBarExtra` label binds to — no `NSStatusItem` access needed.
- **Status line** in the menu, a non-clickable row showing the last outcome:

```
Copiste
─────────────────────────────
Paste Text from Image    ⌥⌘O      ← disabled when the clipboard holds no image
Copy Text from Image    ⌥⌘⇧O
─────────────────────────────
Recognized 14 lines               ← status line
─────────────────────────────
Settings…                 ⌘,
Quit                      ⌘Q
```

Status strings:

| Condition | Text |
| --- | --- |
| success | `Recognized <n> lines` |
| no image on clipboard | `No image on the clipboard` |
| Vision returned nothing | `No text found in the image` |
| Vision threw | `Could not read the image` |
| AX missing, paste action | `Accessibility permission needed to paste` |
| file URL unreadable | `Could not open the copied file` |
| idle (launch) | `Ready` |

### 3.5 Permissions

- **Accessibility** (`AXIsProcessTrusted()`) — required *only* to synthesize `⌘V`, i.e. only
  for `⌥⌘O`. Checked at action time, not polled. On failure: set the status line, prompt
  once via `AXIsProcessTrustedWithOptions`, and open
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
- **No other permissions.** No camera, no screen recording, no network, no Apple Events.
  The entitlements file is empty apart from what ad-hoc signing requires.

> **Signing and the permission grant.** An ad-hoc signed app is identified by the hash of its
> binary, so every rebuild invalidates the Accessibility grant while System Settings still
> shows the toggle on — indistinguishable, from the user's side, from the app being broken.
> `Scripts/setup_signing.sh` creates a self-signed certificate in its own keychain (no sudo,
> never trusted system-wide) and `package_app.sh` uses it when present. The designated
> requirement becomes `identifier "com.bixentemal.copiste" and certificate root = H"…"`,
> which is stable across builds, so the grant persists. Verified empirically: two
> consecutive builds produce different `CDHash` values and an identical designated
> requirement. `tccutil reset Accessibility <bundle id>` re-arms the prompt; the dev build
> is `com.bixentemal.copiste.debug`.

### 3.6 Settings

A single pane:

- Shortcut recorder — Paste Text from Image (default `⌥⌘O`), with an enable checkbox.
- Shortcut recorder — Copy Text from Image (default `⌥⌘⇧O`), with an enable checkbox.
- `Launch at login` toggle — **off by default** (`SMAppService.mainApp`).
- Accessibility status row + "Open System Settings…" button.

All persisted in `UserDefaults` via `@AppStorage`; shortcuts persisted by the
`KeyboardShortcuts` package under its own keys.

---

## 4. The recognition pipeline

### 4.1 Recognition

`RecognizeTextRequest` (Vision, macOS 15 Swift API):

- `recognitionLevel = .accurate`
- `usesLanguageCorrection = true`
- automatic language detection (no explicit language list)

Runs on the image `Data`. Returns `[RecognizedTextObservation]`, each with a top candidate
string and a **normalized** bounding box, in arbitrary order.

### 4.2 Layout reconstruction

Vision gives characters and geometry but discards **all** whitespace: no indentation, no
blank lines, and no reading order. Joining observations with `\n` flattens a screenshot of
indented code into a left-flush wall of text. This pass rebuilds the whitespace from the
geometry alone.

> **Provenance.** This algorithm is original work by the author, first written for the
> `bixentemal/Trimmy` fork (commit `c351264`, 2026-08-27). It does not exist in upstream
> `steipete/Trimmy`, which has no OCR feature. It carries Copiste's own license — no
> third-party terms apply.

**Pass A — denormalize.** Read the true pixel size via
`CGImageSourceCopyPropertiesAtIndex` (`kCGImagePropertyPixelWidth/Height`) and scale every
box into pixels, so all distances are comparable. If the size cannot be read, degrade
gracefully to `\n`-joined top-candidate strings.

**Pass B — order, and merge into visual lines.** Sort fragments by `midY` descending
(Vision's y grows upward → top to bottom). Walk them in order: if a fragment's vertical
centre falls within the previous line's box, it is on the *same* visual line — merge it,
placing it left or right by comparing `minX`, and union the rectangles. This preserves
two-column layouts, trailing badges, and split code lines instead of stacking them.

**Pass C — measure one character.** For each line, `rect.width / text.count` is that line's
mean glyph width. Take the **median across all lines** as the character unit. This is what
makes indentation resolution- and font-size-independent: the unit is derived from the
recognized text itself, never hardcoded. Fallback when no line is measurable: median line
height × 0.5.

**Pass D — indentation → leading spaces.** For each line,
`(minX − min(all minX)) / characterWidth` is an offset in characters — the leftmost line on
the page is 0 by construction. Rounding each offset on its own would stagger visually
aligned lines whenever the measurement wobble straddles a `.5` boundary (2.4 and 2.6 → two
and three spaces). So offsets are first grouped into shared **indent levels**: walk them in
ascending order and open a new level whenever an offset sits more than **0.75 characters**
past the current one; otherwise absorb it into the current level. Each line then snaps to
its nearest level, rounds to an `Int`, and is clamped to **[0, 16]** so a stray glyph in the
margin cannot push a line out to column 300.

> **One change from the original implementation.** The original anchors each level at the
> *first* (leftmost) offset that created it. When a group's wobble spans slightly more than
> the tolerance, its last member falls outside the anchor's reach and opens a second level —
> and the snapping step then sends the upper half of the group to that second level,
> producing exactly the staggering the grouping exists to prevent. Four visually aligned
> bullets measuring 1.9, 2.0, 2.6, 2.7 come out as `2, 2, 3, 3`, no better than plain
> rounding.
>
> Copiste keeps each level at the **running mean** of the offsets absorbed into it, so a
> level tracks the middle of its group rather than its left edge:
>
> ```swift
> if let level = levels.last, offset - level <= Layout.indentClusterTolerance {
>     let n = counts[counts.endIndex - 1]
>     levels[levels.endIndex - 1] = (level * Double(n) + offset) / Double(n + 1)
>     counts[counts.endIndex - 1] = n + 1
> } else {
>     levels.append(offset)
>     counts.append(1)
> }
> ```
>
> The same four bullets now converge on one level at 2.3 and all render at 2 spaces. Two
> further effects: levels become centres rather than edges, so nearest-level snapping agrees
> with group membership instead of contradicting it; and the absorb branch stops being an
> empty statement, which in the original reads as dead code even though the omission is
> deliberate.
>
> Genuine indent steps are unaffected — any spacing of ≥ 0.75 characters still opens a new
> level, and real indents are at least a full character apart. The mean does lag a steadily
> drifting run by up to half the tolerance, delaying a split by about one line; §8 pins both
> the straddle case and the drift case with tests.

**Pass E — vertical gaps → blank lines.** Gap between consecutive line centres; take the
**median** as the normal line pitch. A gap ≥ **1.5 ×** median is a paragraph break, emitting
`round(gap / median) − 1` blank lines, capped at **2**.

**Worked example.** Five fragments arrive in arbitrary order:

```
fragment              box (x, y, w, h) px
"• Tag the release"   (120, 300, 204, 20)
"Deploy checklist"    (100, 420, 192, 22)
"- use vMAJOR.MINOR"  (160, 270, 216, 18)
"• Run the test"      (120, 330, 168, 20)
"suite"               (315, 330,  60, 20)
```

- **B** sorts by y: 420, 330, 300, 270. `suite` has midY 340, inside `• Run the test`'s box,
  and minX 315 > 120 → merges to the right as `• Run the test suite`.
- **C** median glyph width = 12 px (each box above is 12 px per character).
- **D** leftmost minX = 100 → offsets 0, 1.67, 1.67, 5.0 → levels {0, 1.67, 5.0} →
  indents 0, 2, 2, 5.
- **E** pitches 90, 30, 30 → median 30. First gap is 3× median → `round(90/30) − 1 = 2`
  blank lines (at the cap).

Output:

```
Deploy checklist


  • Run the test suite
  • Tag the release
     - use vMAJOR.MINOR
```

### 4.3 Tunables

Collected in one `enum Layout` so they are visible and testable in one place:

| Constant | Value | Meaning |
| --- | --- | --- |
| `characterWidthRatio` | 0.5 | fallback glyph width as a fraction of line height |
| `indentClusterTolerance` | 0.75 | characters within which offsets share an indent level |
| `maximumIndent` | 16 | clamp on leading spaces |
| `paragraphGapRatio` | 1.5 | gap/pitch ratio that starts a paragraph |
| `maximumBlankLines` | 2 | cap on blank lines per gap |

---

## 5. Architecture

### 5.1 Module boundary

```
CopisteCore   pure, UI-free, no AppKit/Vision — [RecognizedLine] -> String
   ▲
   │ depends on
Copiste       AppKit + Vision + SwiftUI; adapters, UI, hotkeys, permissions
```

`CopisteCore` knows nothing about Vision or pasteboards. It receives an array of
`RecognizedLine { text: String, rect: CGRect }` — already in pixels — and returns the
rendered string. This is what makes passes B–E testable against fixture geometry with no
image, no Vision call, and no permissions.

### 5.2 Data flow

```
   ⌥⌘O / ⌥⌘⇧O                menu click
        │                        │
        └──────────┬─────────────┘
                   ▼
            ActionRunner  (re-entrancy guard, status publishing)
                   │
        ┌──────────┴──────────┐
        ▼                     ▼
  ClipboardImageSource   Accessibility.ensureTrusted()   ← paste mode only
        │  Data + UTI
        ▼
  TextRecognizer   Vision → [RecognizedLine] (pixels)
        │
        ▼
  CopisteCore.render(lines:)   → String
        │
        ▼
     Delivery
        ├── .paste : write text → synth ⌘V → +200 ms → restore image
        └── .copy  : write text
                   │
                   ▼
              StatusReporter → menu status line + icon flash
```

### 5.3 File layout

```
copiste/
├── Package.swift                      one dependency: KeyboardShortcuts (≥2.4.0)
├── version.env                        MARKETING_VERSION / BUILD_NUMBER
├── Copiste.entitlements
├── LICENSE                            MIT © Vincent Malet
├── README.md
├── docs/SPEC.md                       this file
├── Artwork/copiste-logo.png           the source mark; icons are derived from it
├── Icon.icns                          generated, git-ignored
├── Scripts/
│   ├── package_app.sh                 build → assemble .app → ad-hoc sign
│   ├── compile_and_run.sh             kill → build → test → package → launch
│   ├── kill_copiste.sh
│   ├── setup_signing.sh               once: local code-signing identity
│   ├── make_icons.sh                  template glyphs + Icon.icns
│   └── make_icons.py                  luminance → template alpha, box downsample
├── Sources/
│   ├── CopisteCore/
│   │   ├── RecognizedLine.swift       struct { text, rect }
│   │   └── TextLayout.swift           passes B–E (~140 L)
│   └── Copiste/
│       ├── CopisteApp.swift           @main, MenuBarExtra, AppDelegate(.accessory)
│       ├── MenuContent.swift          2 actions, status line, Settings, Quit
│       ├── ActionRunner.swift         orchestration + @Published status
│       ├── ClipboardImageSource.swift pasteboard / file-URL image reading
│       ├── TextRecognizer.swift       Vision adapter (pass A)
│       ├── Paster.swift               pasteboard write, ⌘V, restore
│       ├── Hotkeys.swift              2 shortcut names + registration
│       ├── Accessibility.swift        trust check + prompt, behind `AccessibilityGate`
│       ├── MenuIcon.swift             resource lookup with SF Symbol fallback
│       ├── SettingsWindow.swift       opens Settings and raises it to the front
│       └── Settings.swift             @AppStorage + settings pane
│           Resources/                 MenuIcon{,Off}{,@2x}.png — 18×18 template glyphs
└── Tests/
    ├── CopisteCoreTests/              layout fixtures, indent drift, gaps
    └── CopisteTests/                  pasteboard source, delivery with a fake paster
```

### 5.4 Key type contracts

```swift
// CopisteCore
public struct RecognizedLine: Sendable { public var text: String; public var rect: CGRect }
public enum TextLayout {
    public static func render(_ fragments: [RecognizedLine]) -> String
}

// Copiste
enum ClipboardImageSource {
    struct Image { let data: Data; let type: NSPasteboard.PasteboardType }
    static func read(from: NSPasteboard) -> Image?      // pasteboard data, else file URL
    static func hasImage(on: NSPasteboard) -> Bool      // cheap check for menu enablement
}

enum TextRecognizer {
    static func recognize(_ data: Data) async throws -> String   // pass A + Core.render
}

protocol Pasting { func paste() }                       // injectable for tests
struct KeystrokePaster: Pasting                         // CGEvent ⌘V

enum Delivery { case paste, copy }

@MainActor protocol AccessibilityGate {                  // injectable permission check
    var isTrusted: Bool { get }
    func requestPermission()
}

@MainActor final class ActionRunner: ObservableObject {
    @Published private(set) var status: ActionStatus
    @Published private(set) var flash: ActionStatus?     // drives the icon, clears after 1 s
    init(
        pasteboard: NSPasteboard = .general,
        paster: any Pasting = KeystrokePaster(),
        accessibility: any AccessibilityGate = SystemAccessibility(),
        recognize: @escaping @Sendable (Data) async throws -> String = TextRecognizer.recognize)
    func run(_ delivery: Delivery) async
}
```

> **Deviation from the original design.** `ActionRunner` takes two more seams than planned:
> the recognizer as a closure, and the permission check behind `AccessibilityGate`. Both were
> forced by testing — the delivery paths could otherwise only be exercised by running Vision
> for real, and the paste path only by granting Accessibility to the test runner. Each
> defaults to the production implementation, so no call site outside tests passes them.

### 5.5 Dependencies

| Package | Why | Alternative rejected |
| --- | --- | --- |
| `sindresorhus/KeyboardShortcuts` ≥ 2.4.0 | configurable global shortcuts, persistence, and a drop-in `Recorder` view for Settings | raw Carbon `RegisterEventHotKey` + a hand-written recorder ≈ 200 fiddly lines |

Nothing else. No Sparkle, no MenuBarExtraAccess (the icon-state trick in §3.4 removes the
need for direct `NSStatusItem` access), no third-party OCR.

### 5.6 Deliberately absent

Everything below was considered and left out to keep the codebase at one sitting's worth of
reading: clipboard monitoring, copy event taps, source-app tracking, app/site exclusion
lists, per-app behaviour, text post-processing, a CLI, auto-update, telemetry, multi-pane
settings.

---

## 6. Edge cases & failure handling

| Case | Behaviour |
| --- | --- |
| Clipboard holds text only | menu items disabled; hotkey sets `No image on the clipboard` |
| Clipboard holds a non-image file URL | `Could not open the copied file` |
| Image is huge (e.g. a 6K screenshot) | no size cap; Vision handles it. Recognition is async and off the main actor, so the UI never blocks |
| Second invocation while one is running | `ActionRunner` re-entrancy guard drops the second; no queueing |
| Vision returns zero observations | `No text found in the image` — clipboard untouched |
| Vision throws | `Could not read the image` — clipboard untouched |
| Pixel size unreadable | degrade to plain `\n`-joined lines (still useful) |
| AX not granted, `⌥⌘O` | prompt + status line; the copy action still works |
| Permission granted after a complaint | `displayStatus` downgrades a `needsAccessibility` status to `Ready` once the permission is present, so the menu cannot keep reporting a problem the user has already fixed |
| Settings opened from the menu | an `.accessory` app is never active, so the window would open *behind* the user's current app; `SettingsOpener` activates Copiste and raises the window explicitly. Reopening the app from Finder or the Dock opens Settings too, since an accessory app has no windows to restore |
| Frontmost app changes between OCR and `⌘V` | accepted risk — the paste lands in whatever is frontmost, same as any paste. Recognition is fast enough that this needs deliberate effort to hit |
| Restore races the paste | 200 ms delay before restoring, matching the debounce that works reliably in practice |
| App has no image but user opens the menu | actions greyed out via `hasImage(on:)` — a cheap `availableType(from:)` check, no data copy |

---

## 7. Icon

The artwork has two 1024×1024 sources: a full feather logo and a simplified menu-bar mark,
both drawn as light glyphs on a near-black ground.
macOS menu-bar icons must be **template images** — the glyph in solid black with alpha,
fully transparent background, `isTemplate = true` — so the system recolours them for light
and dark menu bars.

Two derivations are needed:

- `MenuIcon.png` (18×18) + `@2x` (36×36) — the simplified mark as a transparent template.
  Plus a slashed `MenuIconOff` variant for the failure flash.
- `Icon.icns` — the full feather artwork including the dark ground, for the bundle and About.

`Scripts/make_icons.sh` derives the menu resources from `Artwork/copiste-mark.png` and uses
`sips` to build the app-icon representations from `Artwork/copiste-logo.png`.

Resources are loaded through a small `Bundle` lookup helper with fallbacks (main bundle
Resources → SwiftPM `Copiste_Copiste.bundle` → dev path), avoiding the `Bundle.module` trap
that requires patching in the reference project.

---

## 8. Build, test, release

```sh
swift build                      # dev build
swift test                       # CopisteCore + Copiste suites (Swift Testing)
./Scripts/compile_and_run.sh     # kill → build → test → package → launch, for iterating
./Scripts/package_app.sh release # Copiste.app, ad-hoc signed
swiftformat . && swiftlint lint  # 4-space, LF, 120 cols
```

`package_app.sh` responsibilities: `swift build -c <conf>` → assemble `Copiste.app` →
generate `Info.plist` from `version.env` (`LSUIElement`, `LSMultipleInstancesProhibited`,
`LSMinimumSystemVersion 15.0`) → copy SwiftPM resource bundles into `Contents/Resources` →
convert `Icon.icon`/artwork to `.icns` → `xattr -cr` → ad-hoc `codesign`. No framework
embedding, no notarization step, no appcast.

**Distribution.** Unsigned and un-notarized, like the reference fork: users unzip, move to
`/Applications`, and run `xattr -dr com.apple.quarantine /Applications/Copiste.app`.
Documented in the README.

### Test plan

`CopisteCoreTests` — the layout algorithm, with hand-built fixture geometry:

- fragments in shuffled order sort top-to-bottom correctly
- two fragments sharing a visual line merge left-to-right; a third below does not
- indent levels: 0/2/5 example from §4.2 renders exactly
- **straddle**: offsets 2.4 and 2.6 must land on one shared indent, not 2 and 3
- **wide wobble**: offsets 1.9, 2.0, 2.6, 2.7 must all render at 2 spaces — the case the
  running-mean change exists for
- **no over-grouping**: offsets a full character apart must stay distinct levels
- **drift**: 12 lines each 0.3 characters further right than the last must eventually split
  into new levels rather than chaining into one
- a stray far-right fragment clamps at 16 spaces rather than exploding the line
- paragraph gaps: 1× pitch → none, 1.5× → one blank, 4× → capped at 2
- single line, empty input, and all-empty-strings do not crash

`CopisteTests`:

- `ClipboardImageSource` prefers PNG over TIFF; reads a file URL; rejects a `.txt` URL
- delivery `.copy` leaves text on a fake pasteboard and restores nothing
- delivery `.paste` calls the injected `Pasting` exactly once and restores the original
  image data and UTI
- `ActionRunner` drops a re-entrant invocation

---

## 9. Open items

1. **Version control.** The repository is not under git yet; no commits have been made.
2. **Distribution.** No release workflow exists. Building from source is the only route.

---

## 10. Decision log

| # | Decision | Rationale |
| --- | --- | --- |
| 1 | Restore the image to the clipboard after `⌥⌘O` | the user's copy survives the paste; matches the reference behaviour |
| 2 | Accept image files copied in Finder, not just pasteboard image data | ~15 lines; makes "copy a screenshot file, hit the shortcut" work |
| 3 | Status line + icon flash rather than notifications | no notification permission, no UI chrome, and the AX-permission failure is otherwise undiagnosable |
| 4 | Launch at login present but off by default | menu-bar apps need it; opting in should be the user's move |
| 5 | Layout algorithm is the author's own work | verified: single commit `c351264` by the author, absent from all upstream refs; no third-party license applies |
| 6 | Paste mechanism and build scripts written fresh | the `CGEvent` ⌘V idiom is generic, but writing it fresh removes the provenance question entirely |
| 7 | No clipboard monitoring | the single largest source of complexity in the reference project, and unnecessary for a pull-based tool |
| 8 | Pure `CopisteCore` target | makes the only non-trivial algorithm testable without Vision, AppKit, or permissions |
| 9 | Indent levels track the running mean of their members, not their leftmost member | fixes visually aligned lines splitting across two levels when wobble exceeds the tolerance; supersedes an earlier, incorrect claim that the original could chain across boundaries |
| 10 | `ActionRunner` takes injectable recognizer and permission gate | the delivery and permission paths are otherwise untestable without running Vision and granting Accessibility to the test runner |
| 11 | Menu-bar glyph derived by mapping luminance to alpha, not hand-traced | the source mark is a light glyph on a dark plate; luminance is exactly the template alpha channel, and `Scripts/make_icons.sh` makes it reproducible |
| 12 | Development builds are signed with a self-signed certificate, not ad-hoc | ad-hoc identity is the code hash, so every rebuild revoked Accessibility while System Settings still showed the toggle on; a certificate-based designated requirement is stable across builds |
| 13 | Settings is opened via a notification serviced from the status-item label, not `SettingsLink` | `SettingsLink` cannot activate an accessory app, so the window opened behind the user's current app; the environment's `openSettings` action needs a living view, and menu content is torn down as the menu closes |
