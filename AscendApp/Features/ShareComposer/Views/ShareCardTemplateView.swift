import SwiftUI
import UIKit

/// A full card template, laid out in the format's design space and scaled to fit
/// whatever it is given.
///
/// This replaced six hand-written SwiftUI functions. Adding a card is now an edit
/// to `share-card-templates-v1.json` plus a screenshot — no Swift, no new code
/// path, which is what `CLAUDE.md`'s content-driven rule asks for.
struct ShareCardTemplateView: View {
    static let aspectRatio = ShareCardFormat.aspectRatio

    let template: ShareCardTemplate
    let context: ShareCardRenderContext
    var artwork: ShareCardArtworkSource = .none

    var body: some View {
        GeometryReader { geo in
            let designSize = ShareCardFormat.designSize
            let scale = min(geo.size.width / designSize.width, geo.size.height / designSize.height)

            ZStack {
                card
                    .frame(width: designSize.width, height: designSize.height)
                    .scaleEffect(scale)
                    .frame(width: designSize.width * scale, height: designSize.height * scale)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        // The card is a fixed design that scales as a unit; it must not reflow
        // with the reader's text size, or the canvas would stop matching the export.
        .dynamicTypeSize(.large)
    }

    @ViewBuilder
    private var card: some View {
        ZStack {
            if let background = template.background {
                ShareCardFillView(fill: background, context: context)
            }
            ShareCardRenderer(node: template.root, context: context, artwork: artwork)
        }
    }
}

extension ShareCardRenderContext {
    /// The context a template renders against: every stat this workout resolves,
    /// plus the injected Best Effort and Totals values, on the brand palette.
    ///
    /// Built once per card. A template names stats it may not get — an unresolved
    /// reference drops its element rather than printing a placeholder.
    static func template(
        stats: [ResolvedShareStat],
        bestEfforts: [ResolvedShareStat],
        weeklyTotals: [ResolvedShareStat],
        splits: ResolvedShareSplits?
    ) -> ShareCardRenderContext {
        var table: [ShareStatRef: ResolvedShareStat] = [:]
        for stat in stats {
            table[ShareStatRef(kind: stat.kind)] = stat
        }
        for effort in bestEfforts {
            table[ShareStatRef(kind: .bestEffort, injectedStatKey: effort.label)] = effort
        }
        // The unkeyed reference means "the most significant one", which is what a
        // template asking for a best effort wants.
        if let first = bestEfforts.first {
            table[ShareStatRef(kind: .bestEffort)] = first
        }
        for total in weeklyTotals {
            table[ShareStatRef(kind: .totals, injectedStatKey: total.label)] = total
        }
        if let first = weeklyTotals.first {
            table[ShareStatRef(kind: .totals)] = first
        }

        return ShareCardRenderContext(stats: table, splits: splits)
    }
}
