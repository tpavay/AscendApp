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
            "summitPoster", "splitsPoster", "raceBibResult", "glassHUD", "officialFinish", "bestEffortStamp"
        ])
        for template in document.templates {
            #expect(!template.title.isEmpty, "\(template.id) has no picker title")
            #expect(template.requires == [.climb], "\(template.id) changed its data requirements")
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

    @Test
    func templatesAreFilteredByTheDataAtHand() throws {
        let store = ShareCardTemplateStore(bundle: .main)
        #expect(store.templates(for: [.climb]).count == 6)
        #expect(store.templates(for: []).isEmpty, "climb cards must not be offered without a climb")
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

}
