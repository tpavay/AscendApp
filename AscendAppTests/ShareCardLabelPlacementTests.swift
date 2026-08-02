import Foundation
import Testing
@testable import AscendApp

/// The defect that would otherwise silently return.
///
/// A sticker's label position used to be accepted by the single-metric renderer
/// and dropped by the multi-metric one, so putting a label on the left and then
/// adding stats threw the choice away. These assert on the card tree the one
/// interpreter draws, which is where the intent now lives.
struct ShareCardLabelPlacementTests {
    /// The acceptance test: place a label to the left, add metrics, switch to a
    /// stacked arrangement — it stays left.
    @Test
    func labelPlacementSurvivesAddingMetricsAndChangingArrangement() throws {
        var sticker = ShareStickerInstance(kind: .steps, labelPlacement: .leading)

        let single = ShareStickerCardBuilder.node(for: sticker, resolvedRefs: sticker.statRefs)
        #expect(Self.placements(in: single) == [.leading])

        // The user adds two more stats and switches to a vertical arrangement.
        sticker.extraStats = [ShareStatRef(kind: .duration), ShareStatRef(kind: .calories)]
        sticker.layout = .column

        let composite = ShareStickerCardBuilder.node(for: sticker, resolvedRefs: sticker.statRefs)
        #expect(sticker.labelPlacement == .leading, "the model must keep the user's choice")
        #expect(
            Self.placements(in: composite) == [.leading, .leading, .leading],
            "every metric must still place its label to the left"
        )
    }

    /// Arrangement and label placement are independent axes. Changing either one
    /// must leave the other alone — the coupling is what produced the defect.
    @Test(arguments: [ShareStatLayout.row, .grid, .column])
    func everyArrangementHonoursEveryPlacement(layout: ShareStatLayout) throws {
        for placement in ShareCardLabelPlacement.allCases {
            var sticker = ShareStickerInstance(kind: .steps, labelPlacement: placement)
            sticker.extraStats = [ShareStatRef(kind: .duration), ShareStatRef(kind: .calories)]
            sticker.layout = layout

            let node = ShareStickerCardBuilder.node(for: sticker, resolvedRefs: sticker.statRefs)
            #expect(
                Self.placements(in: node) == Array(repeating: placement, count: 3),
                "\(layout) dropped \(placement)"
            )
        }
    }

    /// The arrangement still drives the arrangement — it just no longer decides
    /// where labels go.
    @Test
    func arrangementSelectsTheStackAxis() throws {
        var sticker = ShareStickerInstance(kind: .steps, labelPlacement: .below)
        sticker.extraStats = [ShareStatRef(kind: .duration)]

        sticker.layout = .row
        #expect(try Self.stack(in: ShareStickerCardBuilder.node(for: sticker, resolvedRefs: sticker.statRefs)).axis == .horizontal)

        sticker.layout = .column
        let column = try Self.stack(in: ShareStickerCardBuilder.node(for: sticker, resolvedRefs: sticker.statRefs))
        #expect(column.axis == .vertical)
        #expect(column.gridColumns == nil)

        sticker.layout = .grid
        let grid = try Self.stack(in: ShareStickerCardBuilder.node(for: sticker, resolvedRefs: sticker.statRefs))
        #expect(grid.axis == .vertical)
        #expect(grid.gridColumns == 2)
    }

    /// A template expresses placement per element, so one card can put one
    /// metric's label above and another's beside it.
    @Test
    func aCardCanPlaceEachMetricsLabelDifferently() throws {
        let above = ShareStickerCardBuilder.metricNode(
            ref: ShareStatRef(kind: .steps), placement: .above, base: 30
        )
        let leading = ShareStickerCardBuilder.metricNode(
            ref: ShareStatRef(kind: .duration), placement: .leading, base: 30
        )
        let card = ShareCardNode(.stack(ShareCardStack(axis: .horizontal, children: [above, leading])))

        #expect(Self.placements(in: card) == [.above, .leading])
    }

    /// Per-element placement has to survive serialization, because that is how a
    /// template arrives — today from the bundle, later from a hosted payload.
    @Test
    func perElementPlacementRoundTripsThroughJSON() throws {
        let original = ShareCardNode(.stack(ShareCardStack(axis: .vertical, children: [
            ShareStickerCardBuilder.metricNode(ref: ShareStatRef(kind: .steps), placement: .trailing, base: 40),
            ShareStickerCardBuilder.metricNode(ref: ShareStatRef(kind: .date), placement: .none, base: 40)
        ])))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShareCardNode.self, from: data)

        #expect(Self.placements(in: decoded) == [.trailing, .none])
        #expect(decoded == original)
    }

    // MARK: - Helpers

    /// Every metric's label placement, in tree order.
    static func placements(in node: ShareCardNode) -> [ShareCardLabelPlacement] {
        switch node.element {
        case .metric(let metric):
            return [metric.labelPlacement]
        case .stack(let stack):
            return stack.children.flatMap { placements(in: $0) }
        default:
            return []
        }
    }

    static func stack(in node: ShareCardNode) throws -> ShareCardStack {
        guard case .stack(let stack) = node.element else {
            throw StructureError.notAStack
        }
        return stack
    }

    enum StructureError: Error { case notAStack }
}
