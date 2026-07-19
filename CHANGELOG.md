# Changelog

All notable changes to TextMorph are documented here.

## Unreleased

### Fixed

- Corrected Core Text bitmap orientation for layer-backed, flipped AppKit views;
  both resting full-line snapshots and temporary animated slices now render
  upright.
- Preserved a synchronously registered follow-up morph when the previous
  display-link callback completes, preventing reentrant completion handlers from
  losing their new frame registration.
- Made zero-duration opacity changes settle exactly when their delay expires and
  made invalid frame intervals consolidate safely instead of contaminating
  spring state.
- Treated a resolved zero-width proposal as an actual constraint rather than an
  unconstrained initial layout.
- Applied simultaneous font or color replacements even when two full strings
  truncate to the same visible value, without delivering duplicate completion
  callbacks for an already-active visual target.
- Retargeted outgoing visual slices when alignment or container geometry changes
  during an active morph.
- Consolidated active motion when Reduce Motion becomes enabled and tightened
  AppKit teardown, backing-scale, and display-rebinding behavior.

### Performance

- Moved the 256-unit whole-line fallback ahead of per-glyph slice construction,
  keeping pathological input linear and bounding transient layer count.
- Avoided glyph-image-bound queries and bitmap allocation for whitespace-only
  snapshots while retaining their exact typographic advance.
- Replaced repeated nearest-ink boundary scans with precomputed linear passes.

### Validation

- Added presentation-level AppKit raster tests for upright full-line and sliced
  rendering, plus coverage for reentrant display-link registration, synchronous
  follow-up morphs, long-line fallback, whitespace snapshots, invalid frame
  timing, constrained zero width, style replacement, and active layout changes.

## 0.2.0 — 2026-07-19

### Changed

- Rewrote TextMorph as a macOS 15+, AppKit-first package.
- Replaced the UIKit `TextMorphLabel` surface with the native AppKit
  `TextMorphView` API.
- Replaced `UIViewRepresentable`, `UIFont`, and `UIColor` with
  `NSViewRepresentable`, `NSFont`, and `NSColor` throughout the public API.
- Replaced the process-global iOS display-link driver with a view-bound AppKit
  `CADisplayLink` that follows the view's current display.
- Reworked snapshot rendering around a Core Graphics bitmap context while
  retaining full-line Core Text shaping and pixel-aligned layer slices.
- Updated lifecycle handling for AppKit windows, appearance changes, backing
  scale changes, hiding, minimization, and occlusion.
- Updated accessibility to expose one AppKit `.staticText` value containing the
  complete target string.
- Updated Reduce Motion behavior for macOS to use an opacity-only crossfade.

### Added

- Compression-aware head, middle, and tail ellipsis modes, plus an explicit
  no-ellipsis mode.
- SwiftUI proposed-size handling so morphing text participates naturally in
  horizontal layout compression.
- Native AppKit first- and last-baseline metrics.
- AppKit coverage for shaping, rendering, interruption, view lifecycle,
  accessibility, truncation, and display-link behavior.

### Removed

- iOS and UIKit platform support.
- iPhone-specific frame-rate configuration guidance.

## 0.1.0 — 2026-07-19

### Added

- Initial UIKit and SwiftUI prototype with Core Text shaping, identity
  reconciliation, interruptible spring motion, reduced-motion handling, and
  bounded snapshot rendering.
