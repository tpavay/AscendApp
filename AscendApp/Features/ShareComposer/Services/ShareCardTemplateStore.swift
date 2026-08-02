import Foundation

/// Loads the bundled card templates.
///
/// Templates are **data**: adding one is an edit to
/// `share-card-templates-v1.json` plus a screenshot, not a Swift file. Nothing
/// here reaches the network — the composer works offline and must keep working
/// offline, so the bundled payload is the whole source today.
///
/// The shape is deliberately the one `HostedClimbCatalogRepository` already uses
/// for the climb catalog: a versioned payload path, a decoder that tolerates
/// unknown content, and a bundled bootstrap that is always available. If a real
/// reason for remote delivery appears — a campaign card, a template that ships
/// wrong — the same decoder points at that channel and this becomes the
/// bootstrap step. That is a repository, not a rewrite.
struct ShareCardTemplateStore {
    enum StoreError: LocalizedError {
        case missingBundledTemplates

        var errorDescription: String? {
            switch self {
            case .missingBundledTemplates:
                return "The bundled share card templates are missing from the app bundle."
            }
        }
    }

    /// Payload schema version, carried in the filename so a v2 can ship alongside.
    static let payloadVersion = 1
    static let resourceName = "share-card-templates-v\(payloadVersion)"

    private let bundle: Bundle
    private let rendererVersion: Int

    init(bundle: Bundle = .main, rendererVersion: Int = ShareCardFormat.rendererVersion) {
        self.bundle = bundle
        self.rendererVersion = rendererVersion
    }

    /// Templates this binary can draw, in authored order.
    func loadTemplates() throws -> [ShareCardTemplate] {
        let document = try loadDocument()
        return Self.templates(in: document, rendererVersion: rendererVersion)
    }

    /// Templates offered for the data at hand. A card that needs a climb is not
    /// shown without one, rather than rendering with holes in it.
    func templates(for requirements: Set<ShareCardRequirement>) -> [ShareCardTemplate] {
        let templates = (try? loadTemplates()) ?? []
        return templates.filter { requirements.isSuperset(of: $0.requires) }
    }

    func loadDocument() throws -> ShareCardDocument {
        guard let url = Self.bundledURL(in: bundle) else {
            throw StoreError.missingBundledTemplates
        }
        return try Self.decode(try Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> ShareCardDocument {
        try JSONDecoder().decode(ShareCardDocument.self, from: data)
    }

    /// Drops templates authored for a newer renderer. An older binary then offers
    /// fewer cards instead of drawing one wrong — the check that makes the
    /// unknown-element backstop unreachable in practice.
    static func templates(in document: ShareCardDocument, rendererVersion: Int) -> [ShareCardTemplate] {
        document.templates.filter { $0.minRendererVersion <= rendererVersion }
    }

    static func bundledURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: resourceName, withExtension: "json")
            ?? bundle.url(forResource: resourceName, withExtension: "json", subdirectory: "Features/ShareComposer/Resources")
            ?? bundle.url(forResource: resourceName, withExtension: "json", subdirectory: "Resources")
    }
}
