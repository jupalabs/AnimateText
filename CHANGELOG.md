# Changelog

All notable changes to TextMorph are documented here.

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
