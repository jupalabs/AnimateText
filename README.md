# TextMorph

TextMorph is a dependency-free iOS package for fluid, shaping-safe transitions
between arbitrary single-line strings. Shared text stays on screen and moves to
its new position; inserted and removed text follows a restrained spring, scale,
and opacity treatment.

It is designed for interface copy such as `Continue` → `Confirm`, changing
button labels, status text, live captions, and compact values. Digits are treated
as ordinary text. TextMorph intentionally does not implement an odometer or
rolling-number animation.

## Requirements

- iOS 17 or later
- Swift 6.0 or later
- Xcode 16 or later
- SwiftUI or UIKit

## Installation

Add this directory as a local package in Xcode with **File → Add Package
Dependencies… → Add Local…**, then link the `TextMorph` product to the app
target.

From another Swift package, use a local dependency while developing:

```swift
dependencies: [
    .package(path: "../TextMorph")
]
```

and add the product to the consuming target:

```swift
.product(name: "TextMorph", package: "TextMorph")
```

Once this package is hosted, replace the path dependency with its repository
URL and a tagged version.

## SwiftUI

```swift
import SwiftUI
import TextMorph

struct ConfirmationButton: View {
    @State private var isReady = false

    var body: some View {
        Button {
            isReady.toggle()
        } label: {
            TextMorph(isReady ? "Confirm" : "Continue")
                .textFont(.systemFont(ofSize: 17, weight: .semibold))
                .textColor(.white)
                .morphAnimation(.snappy)
        }
    }
}
```

`TextMorph` animates whenever its string changes. It exposes its target text as
one accessibility element and participates in first- and last-text-baseline
alignment. Its frame follows the line's measured size with the same physical
spring used by the glyph motion.

For an immediate update, use a disabled transition:

```swift
TextMorph(label)
    .morphAnimation(shouldAnimate ? .default : .disabled)
```

The complete SwiftUI initializer is:

```swift
TextMorph(
    label,
    font: .preferredFont(forTextStyle: .headline),
    textColor: .label,
    animation: .default,
    granularity: .automatic,
    onAnimationCompletion: {
        // Only the latest, uninterrupted morph calls this closure.
    }
)
```

TextMorph uses `UIFont` and `UIColor` deliberately: the exact same objects are
used for Core Text shaping, bitmap rendering, measurement, and the UIKit API.
This avoids a second approximation of a SwiftUI `Font` or `ShapeStyle`.

## UIKit

```swift
import TextMorph
import UIKit

let label = TextMorphLabel(
    text: "Continue",
    font: .systemFont(ofSize: 17, weight: .semibold),
    textColor: .label,
    animation: .default,
    granularity: .automatic,
    textAlignment: .natural
)

label.translatesAutoresizingMaskIntoConstraints = false

// Later:
label.setText("Confirm", animated: true)
```

`TextMorphLabel` supplies an intrinsic content size. By default, that intrinsic
size follows the spring during a morph. Set
`animatesIntrinsicContentSize = false` when a parent owns sizing or when
repeated Auto Layout invalidation is undesirable:

```swift
label.animatesIntrinsicContentSize = false
```

The UIKit view is noninteractive, does not clip animated overhangs, and behaves
as one `.staticText` accessibility element. `text`, `font`, `textColor`,
`animation`, `granularity`, and `textAlignment` can all be changed after
initialization.

## Animation

TextMorph includes four composed transitions:

- `.default` — quick, restrained, and suitable for most labels.
- `.smooth` — critically damped with a softer response.
- `.snappy` — faster for frequently changing controls.
- `.bouncy` — expressive, with controlled overshoot.

Use `TextMorphAnimation.disabled` to snap immediately, or define a transition:

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

`response` is the period of the corresponding undamped spring. Position, scale,
and size use an exact damped-oscillator solution. Opacity uses a separate short,
linear transition so text does not linger or flash when updates arrive rapidly.

Updates are interruptible. A new target begins from the current presentation
position, velocity, scale, and opacity. If an exiting unit returns during a
rapid reversal, its existing visual identity is resurrected rather than
duplicated. A ten-second safety ceiling consolidates pathological custom springs
that do not decay, preventing an accidental undamped configuration from keeping
the display link alive indefinitely.

## Reconciliation and shaping

`TextMorphGranularity` controls which textual units are eligible to keep their
identity:

| Mode | Behavior |
| --- | --- |
| `.automatic` | Uses words when whitespace is present and extended grapheme clusters otherwise. |
| `.grapheme` | Starts with Swift `Character` boundaries. |
| `.word` | Uses linguistically enumerated words and preserves punctuation and whitespace as graphemes. |

The selected granularity is a preference, not permission to break typography.
TextMorph shapes the complete target line with Core Text first, then coalesces
units that cannot move independently. That includes ligatures, context-sensitive
right-to-left runs, non-monotonic glyph runs, combining sequences, and adjacent
glyphs whose ink overlaps. A shaping-safe word or cluster may therefore animate
as one visual unit.

Stable identities are selected with a longest-common-subsequence reconciliation.
For duplicate characters, equal-length solutions prefer the one with the least
total displacement. This keeps repeated letters from crossing unnecessarily.

## Rendering and performance

The hot path is intentionally small:

1. A text or style update shapes and rasterizes one exact full-line Core Text
   snapshot.
2. Temporary `CALayer` objects display pixel-aligned, non-overlapping slices of
   the immutable old and new snapshots. Slices share their backing image.
3. One shared `CADisplayLink` advances every active TextMorph instance using the
   target presentation timestamp.
4. Each frame updates only position, scale, opacity, and—when requested by
   UIKit—the presented intrinsic size. There is no per-frame text shaping,
   measurement, or rasterization.
5. At rest, all temporary layers are removed and replaced by one exact
   full-line content layer.

The spring step is analytical rather than Euler-integrated, so motion remains
consistent across 60 Hz, 120 Hz, dropped frames, and irregular delivery. The
display-link driver requests a 60–120 Hz range and sleeps completely when no
morph is active. A small per-view snapshot cache avoids reshaping common rapid
reversals and is discarded on memory pressure.

To make 120 Hz updates available on supported iPhones, the host app should add
the following Info.plist key. The system still chooses the actual refresh rate
based on hardware, power, thermal state, and workload.

```xml
<key>CADisableMinimumFrameDurationOnPhone</key>
<true/>
```

See Apple's documentation for
[`CADisplayLink`](https://developer.apple.com/documentation/quartzcore/cadisplaylink)
and
[`CADisableMinimumFrameDurationOnPhone`](https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone).

For pathological lines with more than 256 shaping-safe units, TextMorph
automatically uses a whole-line transition. This bounds transient layer count
and reconciliation work while preserving correctness. Extremely oversized
lines also reduce their private bitmap scale to stay below a 16,384-pixel edge
and 16-megapixel backing-store budget; typographic metrics and layout size remain
unchanged.

## Accessibility and international text

- VoiceOver sees the complete target string, never individual animated units.
- Dynamic `UIColor` values are resolved again when relevant traits change.
- Display-scale changes rebuild the raster at the new native scale.
- Effective left-to-right and right-to-left layout direction is honored.
- With Reduce Motion enabled, updates either crossfade—when the user prefers
  crossfade transitions—or update immediately.
- Entering the background or leaving a window consolidates an active morph to
  its exact target and stops the display link.

## Scope and non-goals

The initial release intentionally supports one uniformly styled, single-line
`String` per view. It does not currently lay out multiline text or accept an
`AttributedString`/`NSAttributedString`. Use one TextMorph per independently
morphing line.

Number formatting belongs to the caller. Values such as `1,024` morph with the
same identity and shaping rules as any other text; digits do not roll vertically
through intermediate values.

## Design lineage

The implementation is native Swift, Core Text, Core Graphics, and Core
Animation. Its design was informed by the identity reconciliation and FLIP
motion in [Torph](https://github.com/lochie/torph), the text API decisions in
[Calligraph](https://github.com/raphaelsalaja/calligraph), and the SwiftUI
animation techniques explored by
[AnimateText](https://github.com/jasudev/AnimateText) and
[Pow](https://github.com/EmergeTools/Pow).
