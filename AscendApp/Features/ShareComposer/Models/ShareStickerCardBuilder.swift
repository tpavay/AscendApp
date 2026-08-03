import Foundation

/// Turns a placed sticker into the same card format a template is written in.
///
/// A sticker is a small card. Building one tree here — instead of picking between
/// a single-metric view and a multi-metric view that took different parameters —
/// is what makes the user's label placement survive adding a stat or changing the
/// arrangement: there is one place that reads it, and every metric goes through it.
///
/// Pure and SwiftUI-free, so the arrangement rules are unit-testable without a
/// view tree.
enum ShareStickerCardBuilder {
    /// Intrinsic value size. A composite runs smaller so several metrics read
    /// together at the same sticker scale.
    static func baseSize(forMetricCount count: Int) -> Double {
        count > 1 ? 30 : 40
    }

    static let splitsBaseSize: Double = 26

    /// How a placement sizes and spaces its value and label, as fractions of the
    /// base size. One table for every metric on every card, so the same placement
    /// looks the same whether it is one sticker or a cell in a grid.
    struct PlacementMetrics {
        var value: Double
        var label: Double
        var tracking: Double
        var spacing: Double
        var labelOpacity: Double
    }

    static func metrics(for placement: ShareCardLabelPlacement) -> PlacementMetrics {
        switch placement {
        case .below:
            return PlacementMetrics(value: 1.0, label: 0.30, tracking: 2.0, spacing: 0.05, labelOpacity: 1)
        case .above:
            return PlacementMetrics(value: 0.92, label: 0.34, tracking: 1.3, spacing: 0.03, labelOpacity: 0.9)
        case .leading, .trailing:
            return PlacementMetrics(value: 0.55, label: 0.34, tracking: 1.0, spacing: 0.20, labelOpacity: 1)
        case .none:
            return PlacementMetrics(value: 1.0, label: 0.30, tracking: 2.0, spacing: 0, labelOpacity: 1)
        }
    }

    /// The card tree for one sticker.
    static func node(
        for instance: ShareStickerInstance,
        resolvedRefs: [ShareStatRef]
    ) -> ShareCardNode {
        if let variant = instance.climbImageVariant {
            return artworkNode(variant: variant)
        }
        if instance.isStructured {
            return splitsNode(textBackground: instance.textBackground)
        }
        return statsNode(instance: instance, refs: resolvedRefs)
    }

    // MARK: - Stat stickers

    private static func statsNode(instance: ShareStickerInstance, refs: [ShareStatRef]) -> ShareCardNode {
        let base = baseSize(forMetricCount: refs.count)
        let cells = refs.map { metricNode(ref: $0, placement: instance.labelPlacement, base: base) }

        let content: ShareCardNode
        if cells.count == 1, let only = cells.first {
            content = only
        } else {
            content = ShareCardNode(.stack(arrangement(instance.layout, base: base, children: cells)))
        }

        return plated(content, base: base, textBackground: instance.textBackground)
    }

    /// One metric, laid out from the sticker's placement. Every cell reads the
    /// same placement — the property the old multi-metric renderer had no
    /// parameter to receive.
    static func metricNode(
        ref: ShareStatRef,
        placement: ShareCardLabelPlacement,
        base: Double
    ) -> ShareCardNode {
        let ratios = metrics(for: placement)
        return ShareCardNode(.metric(ShareCardMetric(
            stat: ref,
            labelPlacement: placement,
            labelPolicy: .automatic,
            value: ShareCardTextStyle(
                role: .heavy,
                size: base * ratios.value,
                tint: ShareCardTint(.value)
            ),
            label: ShareCardTextStyle(
                role: .heavy,
                size: base * ratios.label,
                tracking: ratios.tracking,
                tint: ShareCardTint(.label, opacity: ratios.labelOpacity)
            ),
            spacing: base * ratios.spacing,
            alignment: .center
        )))
    }

    /// Arrangement of a multi-metric sticker. The user picks this independently
    /// of where labels sit; neither overrides the other.
    static func arrangement(
        _ layout: ShareStatLayout,
        base: Double,
        children: [ShareCardNode]
    ) -> ShareCardStack {
        switch layout {
        case .row:
            return ShareCardStack(axis: .horizontal, spacing: base * 0.6, children: children)
        case .column:
            return ShareCardStack(axis: .vertical, spacing: base * 0.34, children: children)
        case .grid:
            return ShareCardStack(
                axis: .vertical,
                spacing: base * 0.6,
                gridColumns: 2,
                rowSpacing: base * 0.38,
                children: children
            )
        }
    }

    // MARK: - Splits

    private static func splitsNode(textBackground: ShareTextBackground) -> ShareCardNode {
        let base = splitsBaseSize
        let table = ShareCardNode(.splits(ShareCardSplitsTableSpec(width: 270, baseSize: base)))
        var modifiers = plate(base: base, textBackground: textBackground, insetRatio: (0.62, 0.68))
        modifiers.shadow = textBackground == .none
            ? ShareCardShadow(tint: ShareCardTint(.hex("000000"), opacity: 0.5), radius: 7, y: 2)
            : nil
        return ShareCardNode(table.element, modifiers: modifiers)
    }

    // MARK: - Climb artwork

    private static func artworkNode(variant: ClimbImageVariant) -> ShareCardNode {
        let size = artworkSize(for: variant)
        return ShareCardNode(
            .artwork(ShareCardArtwork(
                variant: variant,
                overlay: [],
                cornerRadius: 12,
                border: ShareCardStroke(tint: ShareCardTint(.hex("FFFFFF"), opacity: 0.25), width: 1)
            )),
            modifiers: ShareCardModifiers(
                frame: ShareCardFrame(width: size.width, height: size.height),
                shadow: ShareCardShadow(tint: ShareCardTint(.hex("000000"), opacity: 0.4), radius: 8, y: 3)
            )
        )
    }

    static func artworkSize(for variant: ClimbImageVariant) -> (width: Double, height: Double) {
        switch variant {
        case .hero: return (190, 120)
        case .card: return (120, 165)
        case .thumb: return (96, 128)
        }
    }

    // MARK: - Plate

    private static func plated(
        _ node: ShareCardNode,
        base: Double,
        textBackground: ShareTextBackground
    ) -> ShareCardNode {
        var modifiers = plate(base: base, textBackground: textBackground, insetRatio: (0.30, 0.42))
        modifiers.shadow = textBackground == .none
            ? ShareCardShadow(tint: ShareCardTint(.hex("000000"), opacity: 0.45), radius: 6, y: 2)
            : nil
        return ShareCardNode(node.element, modifiers: merge(node.modifiers, into: modifiers))
    }

    private static func plate(
        base: Double,
        textBackground: ShareTextBackground,
        insetRatio: (vertical: Double, horizontal: Double)
    ) -> ShareCardModifiers {
        switch textBackground {
        case .none:
            return ShareCardModifiers()
        case .dark, .grey:
            let tint = textBackground == .dark
                ? ShareCardTint(.hex("000000"), opacity: 0.6)
                : ShareCardTint(.hex("FFFFFF"), opacity: 0.18)
            return ShareCardModifiers(
                padding: ShareCardEdgeInsets(
                    top: base * insetRatio.vertical,
                    leading: base * insetRatio.horizontal,
                    bottom: base * insetRatio.vertical,
                    trailing: base * insetRatio.horizontal
                ),
                background: .color(tint),
                backgroundShape: .roundedRectangle(cornerRadius: base * 0.3)
            )
        }
    }

    /// Keeps a node's own frame/rotation while adopting the plate's chrome.
    private static func merge(_ own: ShareCardModifiers, into plate: ShareCardModifiers) -> ShareCardModifiers {
        var merged = plate
        merged.frame = own.frame ?? plate.frame
        merged.rotationDegrees = own.rotationDegrees ?? plate.rotationDegrees
        merged.opacity = own.opacity ?? plate.opacity
        return merged
    }
}
