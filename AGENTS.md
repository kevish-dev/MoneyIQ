# AGENTS.md — context for AI agents working on MoneyIQ

This file exists so another AI agent (or a future session of yourself) can
pick up this project cold. It's a snapshot of *why things are the way they
are*, not just what the code does — the code itself is the source of truth
for behavior; this is for the reasoning behind it.

Read [finance-app-prd.md](finance-app-prd.md) first — it's the actual
product spec with phase ordering and dependency reasoning. This file is the
delta between "what the PRD says" and "what's actually true after building
it," plus the engineering conventions this repo follows.

## What this project is

A privacy-conscious, native Apple personal finance app (iPhone + iPad;
iOS only — there is no Mac app). SwiftUI, SwiftData, no backend server. See the PRD for the full
product vision; see [README.md](README.md) for what's actually built and
how to run it.

## Project status (as of the last commit touching this file)

**Every PRD phase (1–7) that doesn't strictly need CloudKit is done.**
What's left — shared/family budgets, Handoff, cross-device sync, Home
Screen widgets, push notifications — all trace back to two things:
**CloudKit** and the **App Groups** entitlement, both gated behind the paid
Apple Developer Program, which this project doesn't have. Nothing else is
blocking further free-tier work; if you're picking this up and there's no
paid account yet, look at what's *not* CloudKit/App-Groups-shaped before
assuming something needs to wait.

One feature exists **outside the PRD**: **Split**, a person-to-person IOU/
settle-up tracker (`LedgerContact`/`LedgerEntry`/`LedgerEngine`), added by
explicit user request, not part of the original phased plan. If the PRD and
the code disagree about Split, the code wins — the PRD was never updated to
mention it.

## Architecture

- `MoneyIQCore/` — a Swift package, **all business logic and data models
  live here**, used by the iOS app and its extensions. If you're
  adding a model, a piece of domain logic, or anything that isn't pure
  SwiftUI view code, it goes here, not in `Shared/`.
- `Shared/` — SwiftUI views, compiled directly into the iOS app target
  (not a framework — just source files via `project.yml`'s `sources:`).
- `iOS/MoneyIQ/` — thin app entry point (`@main` struct +
  `ModelContainer` wiring). Almost nothing platform-specific lives here.
- `iOS/MoneyIQWidgets/` — the widget extension hosting the Live Activity.
  ActivityKit is iOS-only.
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec.
  **The `.xcodeproj` is generated and gitignored.** Never hand-edit it —
  edit `project.yml` and run `xcodegen generate`. If you add a new source
  file, you generally don't need to touch `project.yml` (it globs
  directories), but new *targets* (like the widget extension) do need an
  entry there.
- `Config/Secrets.xcconfig` — gitignored, holds real OAuth credentials.
  `Config/Secrets.xcconfig.example` is the checked-in template.

### Code organization convention inside MoneyIQCore

- `Models/` — `@Model` SwiftData classes. Keep them thin: stored properties,
  a memberwise-ish `init`, maybe a computed property or two directly about
  that entity (e.g. `SavingsGoal.progressFraction`). Cross-entity math does
  *not* belong on a model.
- `Insights/` — pure, stateless `enum`-namespaced logic that operates on
  arrays of already-fetched models (`InsightsEngine`, `BudgetEngine`,
  `LedgerEngine`). This is the pattern to follow for any new "compute
  something from a list of X" feature: a static function, no `ModelContext`
  dependency, fully unit-testable without SwiftData. Look at
  `LedgerEngine.swift` for the smallest clean example.
- `Auth/`, `Settings/`, `Import/`, `Intents/`, `LiveActivity/` —
  self-explanatory feature groupings.
- `Persistence/PersistenceController.swift` — the `Schema` array is the
  single source of truth for what SwiftData models exist. **If you add a
  new `@Model` type, you must add it here or it silently won't persist.**

### Testing convention

Every `Insights/*Engine.swift` file has a matching `Tests/` file using
Swift Testing (`import Testing`, `@Test func`, `#expect`). These are pure
function tests — no `ModelContainer` needed except where a test explicitly
exercises `PersistenceController` itself. Run them with:

```bash
cd MoneyIQCore && xcrun --sdk macosx swift test
```

80 tests as of the last commit, across `ReceiptParserTests`,
`ReceiptImagePipelineTests`, `ShareImportInboxTests`, `InsightsEngineTests`,
`BudgetEngineTests`, `SavingsGoalTests`, `LedgerEngineTests`,
`FreelanceProjectEngineTests`, `BackupManagerTests`,
`PersistenceControllerTests`. When you add a new pure
logic function, add tests in this style — don't skip it because "the UI
will catch it," since the UI in this app can't currently be clicked through
reliably in CI/automation (see below).

## Things that are true but not obvious

### iPhone + iPad only; `MoneyIQCore` still lists macOS on purpose

The shipped app is iOS only (universal iPhone/iPad) — the macOS target was
removed and `Shared/` has no `#if os(macOS)` code. `MoneyIQCore/Package.swift`
still declares `.macOS(.v26)`: that is only the *test host* so
`xcrun --sdk macosx swift test` runs the unit tests in seconds without a
simulator. It never ships. Consequence: Core's iOS-only code (ActivityKit,
UIKit) must stay inside `#if os(iOS)`, and `PlatformWindow.swift` keeps a
small AppKit branch so the package compiles on the Mac host.

### The PRD's "needs paid Apple Developer Program" column is wrong in places

Empirically verified, not assumed:

- **Sign in with Apple** genuinely needs it (the capability itself is
  restricted on free/personal teams).
- **Siri Shortcuts / App Intents** do **not**, when implemented as a plain
  `AppIntent` in the main app target (not a separate App Intents
  Extension) — it runs in-process, no App Groups needed. Built and
  verified end-to-end on a free personal team.
- **Live Activities** do **not**, when the widget extension is only
  updated locally by the app itself (`Activity.update`, no push). A
  genuine `app-extension` target, code-signed successfully on a free
  team. Only *Home Screen widgets* (a different WidgetKit surface, reading
  shared data across a real process boundary) need App Groups.
- **CloudKit**, **CloudKit shared zones**, and **APNs push** are correctly
  marked as needing it — those are real.

If you're asked to build something the PRD marks as paid-gated, **verify
empirically by actually building it** before assuming it's blocked. `xcodebuild`
with a personal/free signing team either succeeds or fails with a specific,
legible error — don't guess from the PRD table alone.

### New `@Model` properties must be optional (or nil-tolerant)

SwiftData's lightweight migration adds the column but does **not** backfill
a declared default (`var x: Enum = .foo`) into existing rows — they come in
as nil, and reading one into a non-optional property crashes ("Could not
cast value of type Optional<Any>"). Verified with an old-commit → new-code
store harness (when a since-removed money-in/out field was added). Pattern:
declare the new property optional, e.g. `LedgerContact.lastActivityAt`, and
give readers a non-optional accessor or fallback.

### OCR: use `VNRecognizeTextRequest`, not the async `RecognizeTextRequest`

The newer async `RecognizeTextRequest.perform(on:)` was observed suspending
forever on this project's real receipt images (no CPU, no error, the
continuation never resumed), while `VNRecognizeTextRequest` read the same
images in under a second. `ReceiptParser` runs the latter on a background
queue; `ReceiptImagePipelineTests` has a time-limited OCR test so a hang
fails the suite instead of stalling it. Two related gotchas: decode images
with `ReceiptImageLoader` (ImageIO), never `UIImage(data:)?.cgImage` — the
latter drops EXIF orientation, so a portrait photo is OCR'd sideways — and
don't resample screenshots: a 1% downscale flipped a real "Paid ₹80" to
"Paid 780".

### Share Extension → app handoff works without App Groups

The extension can't write the app's SwiftData store, and
`NSExtensionContext.open(_:)` is Today-widget-only, so a share would
silently go nowhere. What works instead:

- The extension opens MoneyIQ through the `UIApplication` at the top of its
  own responder chain — `open(_:options:completionHandler:)` isn't marked
  extension-unavailable in this SDK (only `sharedApplication` is).
- It **also** always queues the share on a named `UIPasteboard`
  (`ShareImportInbox`): private to the same signing team, persisted by the
  system, no entitlement, no "Allow Paste" prompt. `RootView` drains it
  whenever the app becomes active, so a share still arrives if the app
  switch is ever blocked.

### Deployment target is iOS 26, on purpose

This is required for Liquid Glass (`.glassEffect`, `GlassEffectContainer`,
`.buttonStyle(.glass)`/`.glassProminent`). The SDK in this environment is
Xcode 27 / iOS 27, so 26.0 is the practical floor, not the
ceiling. `MoneyIQCore/Package.swift` needs `swift-tools-version: 6.2` for
the `.v26` platform enum cases to exist at all — if you bump the deployment
target further, check whether the tools-version needs bumping too.

### `GlassEffectContainer` layout gotcha

If a `GlassEffectContainer` is given **multiple top-level children** that
each use `.position()` for absolute placement, the container's own layout
algorithm silently overrides `.position()` — only the first child ends up
placed correctly, others get pulled into whatever default arrangement the
container uses (observed: one child renders in the right place, a second
vanishes entirely rather than appearing where `.position()` said). Fix:
wrap the multiple absolutely-positioned children in a plain `ZStack` first,
and only use `GlassEffectContainer` directly around content that's meant to
optically merge (e.g. the three capsule pieces of the "M" logo, or a
vertical stack of buttons that's naturally single-child from the
container's perspective). See `GlassBackdrop.swift`'s comment for the
concrete case this was found in.

### Swift 6 strict concurrency shows up in real places

This package builds under Swift 6 language mode (tools-version 6.2
defaults to it). Two concrete patterns you'll hit again:

- `AppIntent`'s `static var title`/`description` must be `static let`, not
  `var` — "mutable global state" under strict checking. (`LogExpenseIntent.swift`)
- `Activity<T>.update`/`.end` in this SDK snapshot get flagged as sending a
  MainActor-isolated, non-Sendable value into a `@concurrent` context, even
  though `Activity` is supposed to be `Sendable`. Fixed with
  `@preconcurrency import ActivityKit`, not by fighting the type system —
  this looks like an SDK-snapshot quirk, not a real bug in the calling code.
  (`BudgetLiveActivityManager.swift`)

### `ProgressView` doesn't render through `ImageRenderer` offscreen (macOS)

Rendering a `ProgressView(value:)` through `ImageRenderer` in a bare
command-line executable (no real window) produces a solid bar with a
"no entry" placeholder icon instead of an actual progress bar — looks like
`ImageRenderer` failing to draw the underlying `NSProgressIndicator`
offscreen. The printed/computed values were correct; only the rendering was
broken. Don't use this as a red flag if you see it in a scratch harness —
it's not evidence of a real bug, but also don't treat harness output as
proof `ProgressView` itself is fine without checking the actual app.

### Interactive simulator testing is unreliable in this environment

Two separate issues showed up:

1. Early in this project's history, the iOS Simulator control tool
   (`mcp__Claude_Code_iOS_Simulator__control`) returned a stale-CoreSimulator
   error for an entire session after Xcode was updated mid-session. It
   recovered on its own in a later session without any special fix.
2. Even when attached, `tap` coordinates near the very top (toolbar
   buttons, ~y<100 in a ~874pt-tall device) and very bottom (tab bar,
   ~y>800) are unreliable — taps that should hit a specific button
   sometimes land on something else or nothing, apparently because the
   naive "scale the displayed screenshot pixel position down to device
   points" conversion breaks down near safe-area edges. Taps in the
   vertical middle of the screen were reliably accurate every time.

Given both, this repo leans on **offline `ImageRenderer` harnesses** (a
scratch SPM executable that imports `MoneyIQCore`, builds sample data,
renders a view or calls a function directly, and either prints output or
saves a PNG to inspect) for verification instead of clicking through the
live app, wherever that's sufficient. See any commit message mentioning
"offline harness" for the pattern — they live in the session's scratchpad
directory, not committed to the repo.

### There's a debug-only way to bypass sign-in

`AuthManager.signInAsTestUser()`, wrapped in `#if DEBUG`, and a matching
"Skip Sign In (Debug)" button in `SignInView.swift`. This exists because
real sign-in needs OAuth credentials (`Config/Secrets.xcconfig`) that
aren't configured by default, which otherwise blocks ever reaching the
authenticated part of the app during development. It's compiled out of
Release builds entirely (not just hidden), so it can't ship. If you're
testing the authenticated flow and credentials aren't set up, use this
instead of trying to complete a real OAuth flow in the simulator.

## Build / test commands

```bash
# Regenerate the Xcode project after adding files or changing project.yml
xcodegen generate

# Package unit tests (fast, no simulator needed)
cd MoneyIQCore && xcrun --sdk macosx swift test

# Full app build
xcodebuild -project MoneyIQ.xcodeproj -scheme MoneyIQ-iOS -destination 'id=<simulator-udid>' build
```

Get a simulator UDID with `xcrun simctl list devices`. Prefer building
against a specific booted device ID over `generic/platform=iOS Simulator`
when you intend to actually install/launch afterward.

## What to check before claiming something works

This codebase's own history is full of "compiles" turning out not to mean
"works" (see the Swift 6 concurrency and `GlassEffectContainer` notes
above) — always real build errors caught by actually running `xcodebuild`,
never assumed away. Keep that standard:

1. `xcodegen generate` after touching `project.yml` or adding new targets.
2. `MoneyIQ-iOS` builds clean, and `MoneyIQCore` still compiles for macOS
   (that's how `swift test` runs — see the note on the package below), so
   keep its `#if os(iOS)` guards around UIKit/ActivityKit code.
3. `swift test` in `MoneyIQCore/` for anything touching `Insights/` logic.
4. For UI changes, prefer an offline `ImageRenderer` harness over assuming
   it looks right, given the interactive-simulator caveats above — or use
   the debug skip-auth button plus the simulator control tool if you need
   the real thing, but verify tap coordinates landed where intended rather
   than assuming success from a lack of error.
