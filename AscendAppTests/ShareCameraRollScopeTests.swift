import Foundation
import Testing
@testable import AscendApp

/// The rules the camera roll's scope row has to keep: `All Albums` can never be pushed off, an
/// album never appears twice, the earned slot goes to the album you actually shoot into, and a date
/// window means exactly the interval it says.
///
/// All of it is pure, so none of it needs a photo library or a view tree.
struct ShareCameraRollScopeTests {

    // MARK: - Filter row ordering

    /// `All Albums` is second rather than last because only about four items fit before the row
    /// scrolls. Anywhere further along and a long album name pushes the one item that leads
    /// everywhere else off screen.
    @Test
    func allAlbumsIsAlwaysSecondHoweverLongTheEarnedAlbumsNameIs() {
        let albums = [
            Self.userAlbum(id: "long", title: "Summer 2026 Colorado Trip With Everyone", count: 40, daysAgo: 1),
            Self.smartAlbum(id: "fav", title: "Favorites", count: 12, smart: .favorites)
        ]

        let items = ShareScopeShortcuts.items(
            albums: albums,
            scope: .recents,
            rememberedAlbumID: nil
        )

        #expect(items.first == .recents)
        #expect(items[1] == .allAlbums)
    }

    /// Slot 3 goes to the album most recently shot into, so the climb-photos album is one tap away
    /// on the day of the climb with nothing configured.
    @Test
    func slotThreeIsEarnedByTheMostRecentlyShotIntoAlbum() {
        let albums = [
            Self.userAlbum(id: "old", title: "Med school", count: 44, daysAgo: 400),
            Self.userAlbum(id: "fresh", title: "Ascend Climbs", count: 128, daysAgo: 1)
        ]

        let items = ShareScopeShortcuts.items(albums: albums, scope: .recents, rememberedAlbumID: nil)

        #expect(items[2] == .album(albums[1]))
    }

    /// A remembered album outranks recency: it is the standing habit, and the whole point of
    /// remembering it is that it stays one tap away.
    @Test
    func theRememberedAlbumOutranksTheMostRecentOne() {
        let albums = [
            Self.userAlbum(id: "fresh", title: "Gym", count: 64, daysAgo: 1),
            Self.userAlbum(id: "habit", title: "Ascend Climbs", count: 128, daysAgo: 90)
        ]

        let items = ShareScopeShortcuts.items(albums: albums, scope: .recents, rememberedAlbumID: "habit")

        #expect(items[2] == .album(albums[1]))
    }

    /// A smart album would win the recency race on most phones and never give the slot up, so the
    /// earned slot is the climber's own albums only.
    @Test
    func aSmartAlbumNeverTakesTheEarnedSlot() {
        let albums = [
            Self.smartAlbum(id: "shots", title: "Screenshots", count: 2840),
            Self.userAlbum(id: "mine", title: "Ascend Climbs", count: 12, daysAgo: 30)
        ]

        let earned = ShareScopeShortcuts.earnedAlbum(albums: albums, rememberedAlbumID: nil)

        #expect(earned?.id == "mine")
    }

    /// An empty album is never worth a slot - it is a tap that cannot pay off.
    @Test
    func anEmptyAlbumNeverEarnsASlot() {
        let albums = [Self.userAlbum(id: "empty", title: "Race Day", count: 0, daysAgo: 0)]

        #expect(ShareScopeShortcuts.earnedAlbum(albums: albums, rememberedAlbumID: nil) == nil)
        #expect(ShareScopeShortcuts.earnedAlbum(albums: albums, rememberedAlbumID: "empty") == nil)
    }

    // MARK: - The back item

    /// Opening an album from the grid turns that same slot into a back item, so getting out costs
    /// no extra row and no extra control.
    @Test
    func browsingIntoAnAlbumTurnsSlotTwoIntoABackItem() {
        let album = Self.userAlbum(id: "fav", title: "Favorites", count: 20, daysAgo: 2)
        var scope = ShareCameraRollScope.recents
        scope.selection = .album(album)
        scope.browsedAlbum = album

        let items = ShareScopeShortcuts.items(albums: [album], scope: scope, rememberedAlbumID: nil)

        #expect(items[1] == .back(album))
        #expect(items[1].selection == .allAlbums)
    }

    /// While that slot names an album, the same album is dropped from the shortcuts further along,
    /// or it would appear twice in one row.
    @Test
    func theBrowsedAlbumIsNotAlsoOfferedAsAShortcut() {
        let favorites = Self.smartAlbum(id: "fav", title: "Favorites", count: 629, smart: .favorites)
        var scope = ShareCameraRollScope.recents
        scope.selection = .album(favorites)
        scope.browsedAlbum = favorites

        let items = ShareScopeShortcuts.items(
            albums: [favorites],
            scope: scope,
            rememberedAlbumID: "fav"
        )

        let favoriteEntries = items.filter { item in
            if case .album(let album) = item { return album.id == "fav" }
            return false
        }
        #expect(favoriteEntries.isEmpty)
        #expect(items.filter(\.isBackItem).count == 1)
    }

    /// Choosing a shortcut is the same destination but arrives without a browser to go back to, so
    /// slot 2 stays `All Albums`.
    @Test
    func choosingAShortcutLeavesSlotTwoAsAllAlbums() {
        let album = Self.smartAlbum(id: "fav", title: "Favorites", count: 20, smart: .favorites)
        var scope = ShareCameraRollScope.recents
        scope.selection = .album(album)

        let items = ShareScopeShortcuts.items(albums: [album], scope: scope, rememberedAlbumID: nil)

        #expect(items[1] == .allAlbums)
    }

    /// PhotoKit hands back `localizedTitle` in the device's language, so pinning the Favorites and
    /// Videos shortcuts on their English names drops both from the row on a French phone.
    @Test
    func pinnedShortcutsSurviveALocalizedAlbumTitle() {
        let albums = [
            Self.smartAlbum(id: "fav", title: "Favoris", count: 12, smart: .favorites),
            Self.smartAlbum(id: "vid", title: "Vidéos", count: 8, smart: .videos),
            Self.smartAlbum(id: "shots", title: "Captures d'écran", count: 900)
        ]

        let items = ShareScopeShortcuts.items(albums: albums, scope: .recents, rememberedAlbumID: nil)

        #expect(items.map(\.id) == ["recents", "all-albums", "album-fav", "album-vid"])
    }

    // MARK: - The calendar's visibility rule

    /// The calendar shows whenever photos are on screen and disappears whenever they are not. The
    /// album grid is browsing albums rather than photos, so there is nothing to date-filter yet.
    @Test
    func onlySelectionsThatShowPhotosOfferADateFilter() {
        #expect(ShareCameraRollSelection.recents.showsPhotos)
        #expect(ShareCameraRollSelection.album(Self.smartAlbum(id: "a", title: "A", count: 1)).showsPhotos)
        #expect(!ShareCameraRollSelection.allAlbums.showsPhotos)
    }

    // MARK: - Album grid grouping

    /// An album someone named themselves beats one iOS generated, and an empty smart album is not
    /// worth a tile at all.
    @Test
    func theGridPutsUserAlbumsFirstAndDropsEmptySmartOnes() {
        let albums = [
            Self.smartAlbum(id: "fav", title: "Favorites", count: 12, smart: .favorites),
            Self.smartAlbum(id: "raw", title: "RAW", count: 0),
            Self.userAlbum(id: "mine", title: "Ascend Climbs", count: 5, daysAgo: 1)
        ]

        let sections = ShareScopeShortcuts.gridSections(albums: albums)

        #expect(sections.map(\.title) == ["My Albums", "Media Types"])
        #expect(sections[0].albums.map(\.id) == ["mine"])
        #expect(sections[1].albums.map(\.id) == ["fav"])
    }

    /// An empty album the climber made stays listed, dimmed, rather than vanishing - hiding it is
    /// what makes someone ask where it went.
    @Test
    func anEmptyUserAlbumStaysInTheGrid() {
        let albums = [Self.userAlbum(id: "race", title: "Race Day", count: 0, daysAgo: 3)]

        let sections = ShareScopeShortcuts.gridSections(albums: albums)

        #expect(sections.first?.albums.map(\.id) == ["race"])
    }

    // MARK: - Date windows

    /// A whole year is a year, and the interval is half-open so an asset created exactly on the
    /// boundary cannot land in two windows.
    @Test
    func aYearWindowCoversExactlyThatYear() throws {
        let interval = try #require(ShareDateWindow(year: 2026).dateInterval(calendar: Self.calendar))

        #expect(Self.calendar.component(.year, from: interval.start) == 2026)
        #expect(Self.calendar.component(.month, from: interval.start) == 1)
        #expect(Self.calendar.component(.year, from: interval.end) == 2027)
        #expect(Self.calendar.component(.month, from: interval.end) == 1)
    }

    @Test
    func aMonthWindowCoversExactlyThatMonth() throws {
        let interval = try #require(
            ShareDateWindow(year: 2026, month: 8).dateInterval(calendar: Self.calendar)
        )

        #expect(Self.calendar.component(.month, from: interval.start) == 8)
        #expect(Self.calendar.component(.month, from: interval.end) == 9)
        #expect(Self.calendar.component(.year, from: interval.end) == 2026)
    }

    /// December rolls the year, which is the one arithmetic case a hand-written range gets wrong.
    @Test
    func decemberRollsIntoTheNextYear() throws {
        let interval = try #require(
            ShareDateWindow(year: 2026, month: 12).dateInterval(calendar: Self.calendar)
        )

        #expect(Self.calendar.component(.year, from: interval.end) == 2027)
        #expect(Self.calendar.component(.month, from: interval.end) == 1)
    }

    /// A month outside 1...12 is not a window, and is dropped rather than producing a wrong one.
    @Test
    func anOutOfRangeMonthIsDiscarded() {
        #expect(ShareDateWindow(year: 2026, month: 0).month == nil)
        #expect(ShareDateWindow(year: 2026, month: 13).month == nil)
    }

    // MARK: - Falling back

    /// A remembered album that no longer resolves drops silently to Recents, keeping any date the
    /// climber set. An album they deleted themselves is not news.
    @Test
    func clearingTheAlbumKeepsTheDateWindow() {
        let album = Self.userAlbum(id: "gone", title: "Deleted", count: 4, daysAgo: 9)
        let window = ShareDateWindow(year: 2026, month: 3)
        let scope = ShareCameraRollScope(
            selection: .album(album),
            dateWindow: window,
            browsedAlbum: album
        )

        let cleared = scope.clearingAlbum()

        #expect(cleared.selection == .recents)
        #expect(cleared.dateWindow == window)
        #expect(cleared.browsedAlbum == nil)
    }

    // MARK: - Fixtures

    private static let calendar = Calendar(identifier: .gregorian)

    private static func userAlbum(id: String, title: String, count: Int, daysAgo: Int) -> ShareAlbum {
        ShareAlbum(
            id: id,
            title: title,
            count: count,
            newestAssetDate: Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400),
            kind: .user
        )
    }

    private static func smartAlbum(
        id: String,
        title: String,
        count: Int,
        smart: ShareAlbum.Kind.Smart = .other
    ) -> ShareAlbum {
        ShareAlbum(id: id, title: title, count: count, newestAssetDate: nil, kind: .smart(smart))
    }
}
