/// Controls the textual units reconciled across an update.
public enum TextMorphGranularity: Hashable, Sendable {
    /// Uses words when the value contains whitespace and extended grapheme
    /// clusters otherwise. This is the recommended mode for interface labels.
    case automatic

    /// Reconciles extended grapheme clusters whenever shaping permits it.
    case grapheme

    /// Reconciles linguistically detected words, while preserving punctuation
    /// and whitespace as independent grapheme units.
    case word
}
