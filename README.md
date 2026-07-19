# TextMorph

TextMorph is a dependency-free macOS package for fluid, shaping-safe
transitions between arbitrary single-line strings. Shared text stays visible
and moves to its new position while inserted and removed text follows a
restrained spring, scale, and opacity treatment.

It is designed for native Mac interface copy such as changing branch names,
button labels, status text, compact values, and live captions. Digits are
ordinary text; TextMorph intentionally does not implement an odometer or
rolling-number animation.

## Requirements

- macOS 15 or later
- Swift 6.0 or later
- Xcode 16 or later
- SwiftUI or AppKit

## Installation

Add `https://github.com/jupalabs/AnimateText` in Xcode with **File → Add
Package Dependencies…**, then link the `TextMorph` product to your target.

From another Swift package:

```swift
dependencies: [
    .package(
        url: "https://github.com/jupalabs/AnimateText.git",
        branch: "main"
    )
]
```

Add the product to the consuming target:

```swift
.product(name: "TextMorph", package: "AnimateText")
```

Use a version requirement instead of `main` after the repository publishes a
release tag.

## SwiftUI

```swift
import AppKit
import SwiftUI
import TextMorph

struct BranchTitle: View {
    let branchName: String

    var body: some View {
        TextMorph(
            branchName,
            font: .systemFont(ofSize: 24, weight: .semibold),
            textColor: .labelColor,
            animation: .smooth
        )
        .textTruncation(.middle)
    }
}
```

`TextMorph` updates whenever its string changes. It participates in text
baseline alignment, accepts horizontal compression, and inserts an ellipsis
when the proposed width is narrower than the natural line.

Both the SwiftUI and AppKit surfaces are main-actor isolated. An update made
while the AppKit view is off-window, hidden, minimized, or occluded is applied
immediately; its completion closure can therefore run synchronously.

The complete initializer is:

```swift
TextMorph(
    label,
    font: .preferredFont(forTextStyle: .headline, options: [:]),
    textColor: .labelColor,
    animation: .default,
    granularity: .automatic,
    truncationMode: .tail,
    onAnimationCompletion: {
        // Only the latest uninterrupted morph calls this closure.
    }
)
```

The fluent modifiers mirror those initializer options:

```swift
TextMorph(label)
    .textFont(.systemFont(ofSize: 17, weight: .semibold))
    .textColor(.secondaryLabelColor)
    .morphAnimation(.snappy)
    .granularity(.grapheme)
    .textTruncation(.tail)
    .onAnimationCompletion { finished() }
```

Use `.morphAnimation(.disabled)` for immediate updates.

TextMorph deliberately accepts `NSFont` and `NSColor`. The same native font
and resolved color are used for Core Text shaping, measurement, rasterization,
the AppKit view, and the SwiftUI adapter, avoiding an approximation of a
SwiftUI `Font` or `ShapeStyle`.

## AppKit

```swift
import AppKit
import TextMorph

let titleView = TextMorphView(
    text: "feature/sidebar",
    font: .systemFont(ofSize: 24, weight: .semibold),
    textColor: .labelColor,
    animation: .smooth,
    granularity: .automatic,
    textAlignment: .leading,
    truncationMode: .middle
)

titleView.translatesAutoresizingMaskIntoConstraints = false

// Later:
titleView.setText("feature/window-toolbar", animated: true)
```

`TextMorphView` supplies an intrinsic content size and honors Auto Layout
compression. When its assigned width is narrower than the natural line, it
renders a shaping-safe truncated target rather than drawing beyond its bounds.

By default, an unconstrained view reports its interpolated intrinsic size
during a morph. Disable repeated intrinsic-size invalidation when a parent owns
sizing:

```swift
titleView.animatesIntrinsicContentSize = false
```

The view is intentionally noninteractive and does not intercept mouse events.
Its public `text`, `font`, `textColor`, `animation`, `granularity`,
`textAlignment`, and `truncationMode` properties can all change after
initialization.

## Truncation

TextMorph supports four single-line compression modes:

| Mode | Behavior |
| --- | --- |
| `.tail` | Keeps the beginning and replaces the end with an ellipsis. |
| `.head` | Keeps the end and replaces the beginning with an ellipsis. |
| `.middle` | Keeps both ends and replaces the middle with an ellipsis. |
| `.none` | Draws the complete line without inserting an ellipsis. |

Truncation respects extended grapheme-cluster boundaries. Window resizing
updates the truncated representation immediately, while subsequent text
changes continue to morph normally at the constrained width.

For `.none`, set `titleView.layer?.masksToBounds = true` when the containing
layout should clip overflow.

## Animation

TextMorph includes four composed transitions:

- `.default` — quick and restrained for most labels.
- `.smooth` — critically damped with a softer response.
- `.snappy` — faster for frequently changing controls.
- `.bouncy` — expressive, with controlled overshoot.

Define a custom transition when needed:

```swift
let transition = TextMorphAnimation(
    response: 0.42,
    dampingRatio: 0.9,
    opacityDuration: 0.12,
    insertionDelay: 0.025,
    scale: 0.97,
    verticalOffset: 0.05,
    respectsReducedMotion: true
)
```

Position, scale, and size use an analytical damped-spring solution. Opacity
uses a short linear transition so rapidly changing text does not linger or
flash. Updates are interruptible: each new target begins from the current
presentation position, velocity, scale, and opacity. If an exiting unit returns
during a rapid reversal, its existing visual identity is reused.

A ten-second safety ceiling consolidates pathological custom springs that do
not decay, preventing an undamped configuration from keeping a display link
active indefinitely.

## Reconciliation and shaping

`TextMorphGranularity` controls which textual units are eligible to retain
their identity:

| Mode | Behavior |
| --- | --- |
| `.automatic` | Uses words when whitespace is present and extended grapheme clusters otherwise. |
| `.grapheme` | Starts with Swift `Character` boundaries. |
| `.word` | Uses linguistically enumerated words and preserves punctuation and whitespace as graphemes. |

Granularity is a preference, not permission to break typography. TextMorph
shapes the complete target line with Core Text, then coalesces units that cannot
move independently. This includes ligatures, context-sensitive right-to-left
runs, non-monotonic glyph runs, combining sequences, and adjacent glyphs whose
ink overlaps. A shaping-safe word or cluster may therefore animate as one
visual unit.

Stable identities use longest-common-subsequence reconciliation. For duplicate
characters, equal-length solutions prefer the mapping with the least total
displacement, preventing repeated letters from crossing unnecessarily.

## Rendering and performance

The render path is native AppKit, Core Text, Core Graphics, and Core Animation:

1. A text or style update shapes and rasterizes one exact full-line Core Text
   snapshot.
2. Temporary `CALayer` objects display pixel-aligned, non-overlapping slices of
   immutable old and new snapshots. Slices share their backing image.
3. An AppKit view-bound `CADisplayLink` advances the active morph at the refresh
   cadence of the display containing that view.
4. Frames update only position, scale, opacity, and optionally presented
   intrinsic size. Text shaping and rasterization never occur per frame.
5. At rest, temporary layers are removed and replaced by one exact full-line
   layer. The display link is invalidated and sleeps completely.

The spring step is analytical rather than Euler-integrated, so motion remains
consistent across 60 Hz, 120 Hz, dropped frames, and irregular delivery. A
small per-view snapshot cache avoids reshaping rapid reversals.

Inputs requesting more than 256 textual units are detected before per-glyph
slice construction and automatically use a whole-line transition. This bounds
transient layer count and reconciliation work. Whitespace-only lines preserve
their typographic advance without allocating an empty bitmap. Extremely large
visible lines reduce private bitmap scale to stay below a 16,384-pixel edge and
16-megapixel backing-store budget while preserving typographic layout size.
Interrupted outgoing work is separately capped at 256 units, 16 snapshot
generations, and 16 megapixels of retained raster data.

## Accessibility and international text

- VoiceOver sees one AppKit `.staticText` element containing the complete
  target string; animated glyph layers are never exposed individually.
- Reduce Motion replaces translation and scale with an opacity-only crossfade.
- SwiftUI's Reduce Motion environment and AppKit's system accessibility setting
  produce the same behavior.
- Semantic `NSColor` values are re-resolved when effective appearance changes.
- Moving a window between displays rebuilds snapshots at the destination
  display's backing scale and rebinds animation timing to that view.
- Natural, leading, and trailing alignment honor left-to-right and
  right-to-left interface direction.
- Detaching, hiding, minimizing, or occluding the view consolidates active
  motion and releases its display link.

## Scope and non-goals

TextMorph supports one uniformly styled, single-line `String` per view. It does
not currently lay out multiline text or accept `AttributedString` or
`NSAttributedString`. Use one TextMorph for each independently morphing line.

Number formatting belongs to the caller. A value such as `1,024` follows the
same identity and shaping rules as any other text; digits do not roll through
intermediate values.

## Design lineage

The implementation was informed by the identity reconciliation and FLIP motion
in [Torph](https://github.com/lochie/torph), the text API decisions in
[Calligraph](https://github.com/raphaelsalaja/calligraph), and the SwiftUI
animation techniques explored by
[AnimateText](https://github.com/jasudev/AnimateText) and
[Pow](https://github.com/EmergeTools/Pow).
