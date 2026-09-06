import Foundation

/// One item in the camera roll's filter row.
enum ShareScopeItem: Identifiable, Equatable, Hashable, Sendable {
    case recents
    /// Opens the album grid.
    case allAlbums
    /// The same slot as `allAlbums`, once an album has been opened from that grid. Tapping it goes
    /// back to the grid rather than to Recents.
    case back(ShareAlbum)
    /// A one-tap shortcut to a specific album.
    case album(ShareAlbum)

    var id: String {
        switch self {
        case .recents: return "recents"
        case .allAlbums: return "all-albums"
        case .back(let album): return "back-\(album.id)"
        case .album(let album): return "album-\(album.id)"
        }
    }

    var title: String {
        switch self {
        case .recents: return "Recents"
        case .allAlbums: return "All Albums"
        case .back(let album): return album.title
        case .album(let album): return album.title
        }
    }

    var isBackItem: Bool {
        if case .back = self { return true }
        return false
    }

    /// What selecting this item scopes the grid to.
    var selection: ShareCameraRollSelection {
        switch self {
        case .recents: return .recents
        // The back item returns to the album grid it came from.
        case .allAlbums, .back: return .allAlbums
        case .album(let album): return .album(album)
        }
    }
}

/// Builds the filter row.
///
/// Pure on purpose: the ordering rules - All Albums second so a long album name can never push it
/// off, an earned slot, and no album appearing twice - are the parts most worth testing, and none of
/// them need a photo library or a view tree.
enum ShareScopeShortcuts {
    /// Smart albums that get a fixed shortcut, in the order they appear. Matched on PhotoKit's
    /// subtype rather than its localized title, which is only ever English on an English phone.
    private static let pinnedSmartKinds: [ShareAlbum.Kind.Smart] = [.favorites, .videos]

    static func items(
        albums: [ShareAlbum],
        scope: ShareCameraRollScope,
        rememberedAlbumID: String?
    ) -> [ShareScopeItem] {
        var items: [ShareScopeItem] = [.recents]

        // Slot 2. `All Albums` is deliberately second rather than last: measured at Montserrat's
        // real widths only about four items fit before the row scrolls, so anywhere further along
        // a long album name would push the one item that leads everywhere else off screen.
        if let browsed = scope.browsedAlbum {
            items.append(.back(browsed))
        } else {
            items.append(.allAlbums)
        }

        var shown: Set<String> = Set(scope.browsedAlbum.map { [$0.id] } ?? [])

        if let earned = earnedAlbum(albums: albums, rememberedAlbumID: rememberedAlbumID),
           !shown.contains(earned.id) {
            items.append(.album(earned))
            shown.insert(earned.id)
        }

        for smart in pinnedSmartKinds {
            guard let album = albums.first(where: { $0.kind == .smart(smart) }),
                  !album.isEmpty,
                  !shown.contains(album.id)
            else { continue }
            items.append(.album(album))
            shown.insert(album.id)
        }

        return items
    }

    /// The album that earns slot 3: the one last used, else the one most recently shot into.
    ///
    /// Only the climber's own albums qualify - a smart album like Screenshots would win the
    /// recency race on most phones and never give the slot up.
    static func earnedAlbum(albums: [ShareAlbum], rememberedAlbumID: String?) -> ShareAlbum? {
        if let rememberedAlbumID,
           let remembered = albums.first(where: { $0.id == rememberedAlbumID }),
           !remembered.isEmpty {
            return remembered
        }

        return albums
            .filter { $0.isUserCreated && !$0.isEmpty && $0.newestAssetDate != nil }
            .max { lhs, rhs in
                (lhs.newestAssetDate ?? .distantPast) < (rhs.newestAssetDate ?? .distantPast)
            }
    }

    /// The albums the All Albums grid draws, grouped. User albums first, because an album someone
    /// named themselves beats one iOS generated.
    static func gridSections(albums: [ShareAlbum]) -> [(title: String, albums: [ShareAlbum])] {
        let user = albums.filter(\.isUserCreated)
        let smart = albums.filter { $0.isSmart && !$0.isEmpty }

        var sections: [(title: String, albums: [ShareAlbum])] = []
        if !user.isEmpty { sections.append(("My Albums", user)) }
        if !smart.isEmpty { sections.append(("Media Types", smart)) }
        return sections
    }
}
