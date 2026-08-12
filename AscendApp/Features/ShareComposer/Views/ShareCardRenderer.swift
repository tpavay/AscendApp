import SwiftUI
import UIKit

/// Where climb artwork comes from while a card renders. Export preloads the
/// images because `ImageRenderer` does not wait for async view tasks.
struct ShareCardArtworkSource {
    var climb: Climb?
    var overrides: [ClimbImageVariant: UIImage] = [:]

    static let none = ShareCardArtworkSource()
}

/// The one interpreter for the share-card format.
///
/// Every sticker on the canvas, every recap template, and every exported pixel
/// comes through this `switch`. There is no second renderer, which is the point:
/// a per-element setting cannot be honoured here and dropped somewhere else,
/// because there is nowhere else.
struct ShareCardRenderer: View {
    let node: ShareCardNode
    let context: ShareCardRenderContext
    var artwork: ShareCardArtworkSource = .none

    var body: some View {
        element
            .shareCardModifiers(node.modifiers, context: context)
    }

    @ViewBuilder
    private var element: some View {
        switch node.element {
        case .stack(let stack):
            stackView(stack)
        case .text(let text):
            textView(text)
        case .metric(let metric):
            metricView(metric)
        case .artwork(let spec):
            ShareCardArtworkView(spec: spec, source: artwork, context: context)
        case .splits(let spec):
            if let splits = context.splits,
               !splits.rows.isEmpty || !splits.stepQuintileRows.isEmpty {
                ShareCardSplitsTable(splits: splits, spec: spec, context: context)
            }
        case .rankTab(let spec):
            if let standing = context.standing {
                ShareCardRankTabView(standing: standing, spec: spec, context: context)
            }
        case .standing(let spec):
            if let standing = context.standing {
                ShareCardStandingView(standing: standing, spec: spec, context: context)
            }
        case .progress(let progress):
            progressView(progress)
        case .shape(let shape):
            shapeView(shape)
        case .rule(let rule):
            ruleView(rule)
        case .wordmark(let wordmark):
            AscendWordmark(
                size: wordmark.size,
                letterColor: wordmark.tint.color(in: context),
                markColor: wordmark.tint.color(in: context)
            )
        case .spacer(let minLength):
            Spacer(minLength: minLength.map { CGFloat($0) })
        case .unsupported:
            // A template written for a newer renderer. `minRendererVersion` should
            // have filtered it out long before here; drawing nothing is the
            // backstop that keeps a share from failing outright.
            EmptyView()
        }
    }

    // MARK: - Stack

    @ViewBuilder
    private func stackView(_ stack: ShareCardStack) -> some View {
        let visible = visibleChildren(of: stack)

        switch stack.axis {
        case .horizontal:
            HStack(alignment: stack.alignment.vertical, spacing: stack.spacing) {
                children(visible)
            }
        case .vertical:
            if let columns = stack.gridColumns, columns > 0 {
                VStack(alignment: stack.alignment.horizontal, spacing: stack.rowSpacing ?? stack.spacing) {
                    ForEach(Array(rows(of: visible, columns: columns).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .center, spacing: stack.spacing) {
                            children(row)
                        }
                    }
                }
            } else {
                VStack(alignment: stack.alignment.horizontal, spacing: stack.spacing) {
                    children(visible)
                }
            }
        case .depth:
            ZStack(alignment: stack.alignment.alignment) {
                children(visible)
            }
        }
    }

    private func children(_ nodes: [ShareCardNode]) -> some View {
        ForEach(Array(nodes.enumerated()), id: \.offset) { _, child in
            ShareCardRenderer(node: child, context: context, artwork: artwork)
        }
    }

    /// Drops children that resolve to nothing, then applies `maxVisibleChildren`.
    /// A template lists metrics in priority order; the card takes the first few
    /// this workout actually has.
    private func visibleChildren(of stack: ShareCardStack) -> [ShareCardNode] {
        guard let limit = stack.maxVisibleChildren else { return stack.children }
        return Array(stack.children.filter { $0.resolves(in: context) }.prefix(limit))
    }

    private func rows(of nodes: [ShareCardNode], columns: Int) -> [[ShareCardNode]] {
        stride(from: 0, to: nodes.count, by: columns).map { start in
            Array(nodes[start..<min(start + columns, nodes.count)])
        }
    }

    // MARK: - Text

    @ViewBuilder
    private func textView(_ text: ShareCardText) -> some View {
        if let resolved = context.text(for: text.segments, transform: text.transform)
            ?? context.text(for: text.fallback ?? [], transform: text.transform) {
            styled(Text(resolved), style: text.style)
        }
    }

    private func styled(_ text: Text, style: ShareCardTextStyle) -> some View {
        var run = text
            .font(context.font.swiftUIFont(size: style.size, role: style.role))
            .tracking(style.tracking)
        if style.monospacedDigit { run = run.monospacedDigit() }

        return run
            .foregroundStyle(style.tint.color(in: context))
            .lineLimit(style.lineLimit)
            .minimumScaleFactor(style.minimumScaleFactor ?? 1)
            .multilineTextAlignment(style.alignment?.textAlignment ?? .leading)
            .shareCardTextLegibility(style.legibility)
    }

    // MARK: - Metric

    /// The element that carries the intent. Placement and policy are read here,
    /// once, for every metric on every card.
    @ViewBuilder
    private func metricView(_ metric: ShareCardMetric) -> some View {
        if let stat = context.stat(for: metric.stat) {
            let value = styled(Text(stat.value), style: metric.value)
            let labelText = context.label(for: metric)
            let label = labelText.map { styled(Text($0), style: metric.label) }

            switch metric.labelPlacement {
            case .none:
                value
            case .below:
                VStack(alignment: metric.alignment.horizontal, spacing: metric.spacing) {
                    value
                    label
                }
            case .above:
                VStack(alignment: metric.alignment.horizontal, spacing: metric.spacing) {
                    label
                    value
                }
            case .leading:
                HStack(alignment: .center, spacing: labelText == nil ? 0 : metric.spacing) {
                    label
                    value
                }
            case .trailing:
                HStack(alignment: .center, spacing: labelText == nil ? 0 : metric.spacing) {
                    value
                    label
                }
            }
        }
    }

    // MARK: - Decoration

    private func progressView(_ progress: ShareCardProgress) -> some View {
        GeometryReader { geo in
            Capsule(style: .continuous)
                .fill(progress.track.color(in: context))
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(progress.fill.color(in: context))
                        .frame(width: geo.size.width * min(max(progress.fraction, 0), 1))
                }
        }
        .frame(height: progress.height)
    }

    private func shapeView(_ shape: ShareCardShapeElement) -> some View {
        ZStack {
            if let fill = shape.fill {
                ShareCardFillView(fill: fill, context: context)
                    .clipShape(ShareCardShapeView(kind: shape.shape))
            }
            if let stroke = shape.stroke {
                ShareCardShapeView(kind: shape.shape)
                    .stroke(stroke.tint.color(in: context), style: stroke.strokeStyle)
            }
        }
    }

    private func ruleView(_ rule: ShareCardRule) -> some View {
        // Drawn as a path so a dash pattern is available; a `Divider` cannot dash.
        Rectangle()
            .fill(.clear)
            .frame(height: rule.thickness)
            .overlay {
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: rule.thickness / 2))
                        path.addLine(to: CGPoint(x: geo.size.width, y: rule.thickness / 2))
                    }
                    .stroke(rule.tint.color(in: context), style: rule.strokeStyle)
                }
            }
    }
}

// MARK: - Legibility

extension View {
    /// Applies a text legibility treatment. The one place that decides what each
    /// named intent costs, so a cluster, a template and a sticker cannot drift
    /// into three different answers to "how do I stay readable over a photo".
    ///
    /// The contact shadow is tight and dark rather than broad and soft: blur
    /// spread across a 12pt tracked-out cap dilutes the very ink that separates
    /// it from the highlight behind it.
    ///
    /// The outline is four hard offset shadow copies. `Text` has no stroke, and
    /// the obvious replacement - a `TextRenderer` laying the ring down in one
    /// drawing pass - was built and measured against this: it costs about 1.6×
    /// as much, because a custom renderer opts every run out of SwiftUI's fast
    /// text path, and shrinking its ring from eight offsets to four barely moved
    /// the number. Chained `.shadow`s do nest rather than compose, but a nested
    /// hard shadow on a run of type is cheap, and the whole Splits cluster - the
    /// heaviest thing a climber can place, sixteen treated runs - draws a frame
    /// in well under a tenth of the 120 Hz budget. The numbers are kept in
    /// `ShareStatClusterPresetEvidenceTests`; do not re-litigate this without
    /// re-running them.
    @ViewBuilder
    func shareCardTextLegibility(_ legibility: ShareCardTextLegibility) -> some View {
        switch legibility {
        case .none:
            self
        case .shadow:
            contactShadow()
        case .outline:
            hairlineOutline().contactShadow()
        }
    }

    private func contactShadow() -> some View {
        shadow(color: .black.opacity(0.85), radius: 2.5, x: 0, y: 1.6)
    }

    private func hairlineOutline() -> some View {
        let inset: CGFloat = 0.8
        let ink = Color.black.opacity(0.55)
        return shadow(color: ink, radius: 0, x: inset, y: inset)
            .shadow(color: ink, radius: 0, x: -inset, y: inset)
            .shadow(color: ink, radius: 0, x: inset, y: -inset)
            .shadow(color: ink, radius: 0, x: -inset, y: -inset)
    }
}

extension ShareCardStroke {
    var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: width, dash: dash?.map { CGFloat($0) } ?? [])
    }
}

extension ShareCardRule {
    var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: thickness, dash: dash?.map { CGFloat($0) } ?? [])
    }
}

// MARK: - Modifiers

private extension View {
    /// Applies a node's modifiers in one fixed order — frame, shadow, padding,
    /// background, rotation, opacity. Framing first is what lets a plate fill its
    /// cell and still hug its padding; anything needing a different order nests a
    /// node, which keeps the schema closed instead of growing knobs.
    @ViewBuilder
    func shareCardModifiers(_ modifiers: ShareCardModifiers, context: ShareCardRenderContext) -> some View {
        let shape = modifiers.backgroundShape ?? .rectangle

        self
            .shareCardFrame(modifiers.frame)
            .shareCardShadow(modifiers.shadow, context: context)
            .shareCardPadding(modifiers.padding)
            .shareCardFill(modifiers.background, shape: shape, context: context)
            .shareCardBorder(modifiers.border, shape: shape, context: context)
            .shareCardRotation(modifiers.rotationDegrees)
            .shareCardOpacity(modifiers.opacity)
    }

    /// Every optional modifier is applied only when the node asked for it. A card
    /// is thirty-odd nodes and a sticker re-lays out on every gesture frame, so an
    /// identity geometry effect per node is a cost with nothing to show for it.
    @ViewBuilder
    func shareCardPadding(_ insets: ShareCardEdgeInsets?) -> some View {
        if let insets {
            padding(insets.edgeInsets)
        } else {
            self
        }
    }

    @ViewBuilder
    func shareCardRotation(_ degrees: Double?) -> some View {
        if let degrees, degrees != 0 {
            rotationEffect(.degrees(degrees))
        } else {
            self
        }
    }

    @ViewBuilder
    func shareCardOpacity(_ value: Double?) -> some View {
        if let value, value != 1 {
            opacity(value)
        } else {
            self
        }
    }

    @ViewBuilder
    func shareCardShadow(_ shadow: ShareCardShadow?, context: ShareCardRenderContext) -> some View {
        if let shadow {
            self.shadow(color: shadow.tint.color(in: context), radius: shadow.radius, x: shadow.x, y: shadow.y)
        } else {
            self
        }
    }

    @ViewBuilder
    func shareCardBorder(
        _ border: ShareCardStroke?,
        shape: ShareCardShapeKind,
        context: ShareCardRenderContext
    ) -> some View {
        if let border {
            overlay(
                ShareCardShapeView(kind: shape)
                    .stroke(border.tint.color(in: context), style: border.strokeStyle)
            )
        } else {
            self
        }
    }

    @ViewBuilder
    func shareCardFrame(_ frame: ShareCardFrame?) -> some View {
        if let frame {
            if frame.width != nil || frame.height != nil {
                self.frame(
                    width: frame.width.map { CGFloat($0) },
                    height: frame.height.map { CGFloat($0) },
                    alignment: frame.alignment?.alignment ?? .center
                )
            } else {
                self.frame(
                    maxWidth: frame.maxWidth?.length,
                    maxHeight: frame.maxHeight?.length,
                    alignment: frame.alignment?.alignment ?? .center
                )
            }
        } else {
            self
        }
    }
}

// MARK: - Artwork

/// The climb's artwork on a flexible base.
///
/// The image is laid on `Color.clear` and drawn as an overlay rather than as a
/// sizing member: under `scaledToFill` a landscape hero reports an overflowed
/// width, and used directly that width drove the whole card, stretching every
/// stat off-frame. As an overlay it can overflow visually and clip without ever
/// growing the layout.
private struct ShareCardArtworkView: View {
    let spec: ShareCardArtwork
    let source: ShareCardArtworkSource
    let context: ShareCardRenderContext

    var body: some View {
        Color.clear
            .overlay { image }
            .overlay {
                if !spec.overlay.isEmpty {
                    LinearGradient(
                        colors: spec.overlay.map { $0.color(in: context) },
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .clipShape(clipShape)
            .overlay {
                if let border = spec.border {
                    clipShape.stroke(border.tint.color(in: context), style: border.strokeStyle)
                }
            }
    }

    private var clipShape: ShareCardShapeView {
        ShareCardShapeView(kind: spec.cornerRadius.map { .roundedRectangle(cornerRadius: $0) } ?? .rectangle)
    }

    @ViewBuilder
    private var image: some View {
        if let override = source.overrides[spec.variant] {
            resized(Image(uiImage: override))
        } else if let climb = source.climb {
            ClimbArtworkView(climb: climb, variant: spec.variant)
        } else {
            Color.black
        }
    }

    @ViewBuilder
    private func resized(_ image: Image) -> some View {
        switch spec.contentMode {
        case .fill: image.resizable().scaledToFill()
        case .fit: image.resizable().scaledToFit()
        }
    }
}
