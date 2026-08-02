import Foundation

/// Everything a card needs to draw, resolved **before** rendering starts.
///
/// The interpreter only ever reads from this — it never calls the resolver, so no
/// stat is re-derived while a gesture is in flight. The composer builds one of
/// these when the underlying data changes and hands the same value to the canvas
/// and to the exporter, which is what keeps editing and export identical.
struct ShareCardRenderContext: Equatable, Sendable {
    /// Pre-resolved stats, keyed by the reference a card element names.
    var stats: [ShareStatRef: ResolvedShareStat]
    /// Split rows for the `splits` element.
    var splits: ResolvedShareSplits?
    /// Typeface for every text run; the role picks the weight within it.
    var font: ShareStickerFont
    /// Resolves `ShareCardColor.value`.
    var valueColor: RGBAColor
    /// Resolves `ShareCardColor.label`.
    var labelColor: RGBAColor

    init(
        stats: [ShareStatRef: ResolvedShareStat] = [:],
        splits: ResolvedShareSplits? = nil,
        font: ShareStickerFont = .montserrat,
        valueColor: RGBAColor = .white,
        labelColor: RGBAColor = .lime
    ) {
        self.stats = stats
        self.splits = splits
        self.font = font
        self.valueColor = valueColor
        self.labelColor = labelColor
    }

    func stat(for ref: ShareStatRef?) -> ResolvedShareStat? {
        guard let ref else { return nil }
        return stats[ref]
    }

    // MARK: - Text resolution

    /// Renders a text run, or nil when a segment has no value and no placeholder.
    /// Nil is what makes an element disappear rather than print `--`.
    func text(for segments: [ShareCardTextSegment], transform: ShareCardTextTransform = .none) -> String? {
        guard !segments.isEmpty else { return nil }
        var result = ""
        for segment in segments {
            if let literal = segment.literal {
                result += literal
                continue
            }
            let resolved = stat(for: segment.stat)?.text(for: segment.facet) ?? segment.placeholder
            guard let resolved else { return nil }
            result += resolved
        }
        return transform == .uppercase ? result.uppercased() : result
    }

    /// The label a metric shows, honouring the element's policy and the stat's
    /// own claim to be self-describing. One rule, read by the one renderer.
    func label(for metric: ShareCardMetric) -> String? {
        guard metric.labelPlacement != .none else { return nil }
        guard let stat = stat(for: metric.stat) else { return nil }
        let text = metric.labelOverride ?? stat.label
        guard metric.labelPolicy.showsLabel(for: stat.kind, label: text) else { return nil }
        return text
    }
}

extension ShareCardNode {
    /// Whether this node reads from the workout at all. Decoration — rules,
    /// spacers, plates, bars — does not, so a wrapper full of chrome around one
    /// metric still disappears with that metric.
    var carriesData: Bool {
        switch element {
        case .metric, .splits:
            return true
        case .text(let text):
            return (text.segments + (text.fallback ?? [])).contains { $0.stat != nil }
        case .stack(let stack):
            return stack.children.contains(where: \.carriesData)
        case .artwork, .progress, .shape, .rule, .wordmark, .spacer, .unsupported:
            return false
        }
    }

    /// Whether this node would draw anything for the given data.
    ///
    /// Used for two things a card must get right: dropping a metric whose stat
    /// this workout has no value for, and honouring `maxVisibleChildren` — a
    /// template lists metrics in priority order and takes the first few that
    /// actually resolved, instead of Swift picking for it.
    func resolves(in context: ShareCardRenderContext) -> Bool {
        switch element {
        case .stack(let stack):
            let dataBacked = stack.children.filter(\.carriesData)
            guard !dataBacked.isEmpty else { return true }
            return dataBacked.contains { $0.resolves(in: context) }
        case .text(let text):
            return context.text(for: text.segments, transform: text.transform) != nil
                || context.text(for: text.fallback ?? [], transform: text.transform) != nil
        case .metric(let metric):
            return context.stat(for: metric.stat) != nil
        case .splits:
            return context.splits.map { !$0.rows.isEmpty } ?? false
        case .artwork, .progress, .shape, .rule, .wordmark, .spacer:
            return true
        case .unsupported:
            return false
        }
    }
}
