import Foundation
import Testing
@testable import AscendApp

/// The bundled template payload, and the compatibility rules that let a newer
/// payload reach an older binary without breaking a share.
struct ShareCardTemplateStoreTests {
    @Test
    func theBundledPayloadDecodes() throws {
        let document = try ShareCardTemplateStore(bundle: .main).loadDocument()

        #expect(document.formatVersion == ShareCardTemplateStore.payloadVersion)
        #expect(document.templates.map(\.id) == [
            "result", "poster", "sticker", "standing"
        ])
        for template in document.templates {
            #expect(!template.title.isEmpty, "\(template.id) has no picker title")
            #expect(template.requires == [.climb], "\(template.id) changed its data requirements")
            #expect(template.minRendererVersion == 2)
            #expect(Self.rankTabCount(in: template.root) == 1, "\(template.id) must carry one rank tab")
        }
    }

    /// Adding a template must be a JSON edit. That only holds if nothing in the
    /// payload names a Swift symbol the renderer has to grow a case for.
    @Test
    func everyElementAndStatInThePayloadIsAlreadyKnown() throws {
        let document = try ShareCardTemplateStore(bundle: .main).loadDocument()
        for template in document.templates {
            let unsupported = Self.unsupportedTypes(in: template.root)
            #expect(unsupported.isEmpty, "\(template.id) uses unknown element types: \(unsupported)")
            #expect(template.root.carriesData, "\(template.id) shows nothing from the workout")
        }
    }

    @Test
    func templatesAboveTheRendererVersionAreSkipped() throws {
        let document = ShareCardDocument(formatVersion: 1, templates: [
            ShareCardTemplate(id: "now", title: "Now", minRendererVersion: 1,
                              root: ShareCardNode(.spacer(minLength: nil))),
            ShareCardTemplate(id: "future", title: "Future", minRendererVersion: 99,
                              root: ShareCardNode(.spacer(minLength: nil)))
        ])

        let drawable = ShareCardTemplateStore.templates(in: document, rendererVersion: 1)
        #expect(drawable.map(\.id) == ["now"], "a binary must skip what it cannot draw")
    }

    /// An element type from a newer payload decodes to a no-op instead of
    /// throwing, so one unknown node cannot fail a whole share.
    @Test
    func anUnknownElementDecodesToANoOp() throws {
        let json = Data("""
        {"type": "hologram", "intensity": 3}
        """.utf8)

        let node = try JSONDecoder().decode(ShareCardNode.self, from: json)
        guard case .unsupported(let type) = node.element else {
            Issue.record("expected an unsupported element, got \(node.element)")
            return
        }
        #expect(type == "hologram")
        #expect(!node.resolves(in: ShareCardRenderContext()))
    }

    /// A stat kind this binary does not know behaves exactly like a stat the
    /// workout has no value for: the element disappears.
    @Test
    func anUnknownStatReferenceDropsItsElement() throws {
        let json = Data("""
        {"type": "metric", "stat": "quantumFlux", "value": {"size": 40}}
        """.utf8)

        let node = try JSONDecoder().decode(ShareCardNode.self, from: json)
        guard case .metric(let metric) = node.element else {
            Issue.record("expected a metric, got \(node.element)")
            return
        }
        #expect(metric.stat == nil)
        #expect(!node.resolves(in: ShareCardRenderContext()))
    }

    /// A stack with nothing left in it draws nothing, so it must not report that
    /// it resolved — a sticker whose stats all failed would otherwise be placed as
    /// an empty plate on the canvas and burned into the export.
    @Test
    func anEmptyStackDoesNotResolve() throws {
        let empty = ShareCardNode(.stack(ShareCardStack(axis: .vertical, children: [])))
        #expect(!empty.resolves(in: ShareCardRenderContext()))

        // Decoration-only stacks still resolve: they carry no data to fail.
        let decoration = ShareCardNode(.stack(ShareCardStack(axis: .vertical, children: [
            ShareCardNode(.rule(ShareCardRule()))
        ])))
        #expect(decoration.resolves(in: ShareCardRenderContext()))
    }

    /// The canvas and the exporter both gate on `ShareStickerContent.isEmpty`.
    @Test
    func aStickerWithNoResolvableStatsIsNotPlaced() throws {
        let sticker = ShareStickerInstance(
            kind: .bestEffort,
            extraStats: [ShareStatRef(kind: .duration)]
        )
        let content = ShareStickerContent(
            node: ShareStickerCardBuilder.node(for: sticker, resolvedRefs: []),
            context: ShareCardRenderContext(),
            signature: ShareStickerContentSignature(sticker)
        )

        #expect(content.isEmpty, "a sticker with nothing to draw must reach neither the canvas nor the export")
    }

    /// One bad template must cost one card, not the picker. The element-level
    /// degradation guarantees are worthless if the array is all-or-nothing.
    @Test
    func aMalformedTemplateIsSkippedWithoutLosingTheOthers() throws {
        let json = Data("""
        {"formatVersion": 1, "templates": [
          {"id": "good", "title": "Good", "root": {"type": "spacer"}},
          {"title": "Missing an id", "root": {"type": "spacer"}},
          {"id": "alsoGood", "title": "Also Good", "root": {"type": "spacer"}}
        ]}
        """.utf8)

        let document = try ShareCardTemplateStore.decode(json)

        #expect(document.formatVersion == 1)
        #expect(document.templates.map(\.id) == ["good", "alsoGood"])
    }

    @Test
    func templatesAreFilteredByTheDataAtHand() throws {
        let store = ShareCardTemplateStore(bundle: .main)
        #expect(store.templates(for: [.climb]).count == 4)
        #expect(store.templates(for: []).isEmpty, "climb cards must not be offered without a climb")
    }

    @Test
    func standingIsNeverFilteredByPercentile() throws {
        let templates = ShareCardTemplateStore(bundle: .main).templates(for: [.climb])
        #expect(templates.contains { $0.id == "standing" })

        for percentile in [1, 99] {
            let standing = try #require(ResolvedShareStanding(rank: 10, totalClimbers: 100, percentile: percentile))
            #expect(standing.percentile == percentile)
        }
    }

    /// A stat reference may be written as a bare kind, which is what keeps the
    /// payload readable.
    @Test
    func aStatReferenceDecodesFromABareKind() throws {
        let bare = try JSONDecoder().decode(ShareStatRef.self, from: Data("\"steps\"".utf8))
        #expect(bare == ShareStatRef(kind: .steps))

        let keyed = try JSONDecoder().decode(
            ShareStatRef.self,
            from: Data("{\"kind\": \"bestEffort\", \"injectedStatKey\": \"FASTEST 1K\"}".utf8)
        )
        #expect(keyed == ShareStatRef(kind: .bestEffort, injectedStatKey: "FASTEST 1K"))
    }

    // MARK: - Helpers

    static func unsupportedTypes(in node: ShareCardNode) -> [String] {
        switch node.element {
        case .unsupported(let type):
            return [type]
        case .stack(let stack):
            return stack.children.flatMap { unsupportedTypes(in: $0) }
        default:
            return []
        }
    }

    static func rankTabCount(in node: ShareCardNode) -> Int {
        switch node.element {
        case .rankTab:
            return 1
        case .stack(let stack):
            return stack.children.reduce(0) { $0 + rankTabCount(in: $1) }
        default:
            return 0
        }
    }

}
