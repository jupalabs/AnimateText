/// Horizontal alignment used when a morphing text view is wider than its
/// intrinsic content.
public enum TextMorphAlignment: Hashable, Sendable {
    /// Follows the effective interface layout direction.
    case natural

    /// Aligns to the leading edge.
    case leading

    /// Centers the line.
    case center

    /// Aligns to the trailing edge.
    case trailing
}
