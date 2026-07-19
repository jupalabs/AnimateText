/// The ellipsis placement used when a morphing line is narrower than its
/// natural width.
public enum TextMorphTruncationMode: Hashable, Sendable {
    /// Keeps the complete rendered line without inserting an ellipsis.
    /// The containing view decides whether overflow is clipped.
    case none

    /// Keeps the end of the line and replaces its beginning with an ellipsis.
    case head

    /// Keeps both ends of the line and replaces its middle with an ellipsis.
    case middle

    /// Keeps the beginning of the line and replaces its end with an ellipsis.
    case tail
}
