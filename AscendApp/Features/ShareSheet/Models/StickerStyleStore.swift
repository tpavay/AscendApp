import Foundation

/// Persists the sticker style in `UserDefaults`; the instance is injected for tests.
struct StickerStyleStore {
    static let key = "share.stickerStyle.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> StickerStyle {
        guard let data = defaults.data(forKey: Self.key),
              let style = try? JSONDecoder().decode(StickerStyle.self, from: data) else {
            return .defaults
        }
        return style
    }

    func save(_ style: StickerStyle) {
        guard let data = try? JSONEncoder().encode(style) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
