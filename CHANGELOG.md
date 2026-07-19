# Changelog

All notable changes to TextMorph are documented here.

## 0.1.0 — 2026-07-19

### Added

- `TextMorph`, a SwiftUI view for arbitrary single-line text morphing.
- `TextMorphLabel`, a UIKit view with intrinsic-size animation and explicit
  animated/non-animated updates.
- Core Text shaping and Core Graphics full-line snapshot rendering.
- Shaping-safe coalescing for ligatures, extended graphemes, overlapping ink,
  right-to-left runs, and non-monotonic glyph order.
- Minimum-displacement longest-common-subsequence identity reconciliation.
- Exact, frame-rate-independent spring integration with interruption velocity
  preservation.
- Independent insertion/removal opacity timing, scale, and restrained vertical
  displacement.
- Rapid-reversal resurrection of exiting visual identities.
- A shared, idle-aware 60–120 Hz `CADisplayLink` driver.
- Reduced Motion and crossfade-preference handling.
- VoiceOver, dynamic-color, layout-direction, native-scale, backgrounding, and
  memory-pressure handling.
- A 256-unit safety threshold with whole-line fallback.
- Bounded backing-store dimensions for pathologically large single lines.
- Unit coverage for segmentation, reconciliation, spring math, linear opacity,
  Core Text slicing, interruption, consolidation, completion, and display-link
  lifecycle behavior.

### Explicitly not included

- Rolling or odometer-style number animation.
- Multiline and attributed-string layout.
