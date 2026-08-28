import SwiftUI

/// The All Albums browser: albums drawn as photos, three up, replacing the photo grid in place.
///
/// It presents nothing and pushes nothing - the filter row above stays put and is how the climber
/// leaves, which is why this is a selection rather than a route.
struct ShareAlbumGrid: View {
    let albums: [ShareAlbum]
    let isLoading: Bool
    let selectedAlbumID: String?
    let library: SharePhotoLibrary
    let onSelect: (ShareAlbum) -> Void

    /// Below this a search field is chrome for a list you can already see.
    private static let searchThreshold = 12

    @State private var query = ""

    private let columns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7)
    ]

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sections: [(title: String, albums: [ShareAlbum])] {
        let trimmed = trimmedQuery
        let filtered = trimmed.isEmpty
            ? albums
            : albums.filter { $0.title.localizedStandardContains(trimmed) }
        return ShareScopeShortcuts.gridSections(albums: filtered)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if albums.count > Self.searchThreshold {
                    searchField
                }

                ForEach(sections, id: \.title) { section in
                    Text(section.title.uppercased())
                        .font(.montserratSemiBold(size: 11))
                        .tracking(1.4)
                        .foregroundStyle(Color.customGray)
                        .padding(.horizontal, 10)
                        .padding(.top, 20)
                        .padding(.bottom, 10)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 15) {
                        ForEach(section.albums) { album in
                            tile(album)
                        }
                    }
                    .padding(.horizontal, 10)
                }

                if sections.isEmpty {
                    emptyState
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.customGray)

            TextField("Search albums", text: $query)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.white)
                .tint(Color.ascendAccent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    /// A search miss and an album-less library are different facts, and answering the first when
    /// the climber asked neither is what the loading case used to do on its way through.
    @ViewBuilder
    private var emptyState: some View {
        if isLoading {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
                .accessibilityLabel("Loading albums")
        } else if !trimmedQuery.isEmpty {
            Text("No albums match that.")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(Color.customGray)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        } else {
            VStack(spacing: 8) {
                Text("No albums yet.")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)

                Text("Make one in Photos and it lands here.")
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(Color.customGray)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 40)
            .padding(.top, 40)
        }
    }

    private func tile(_ album: ShareAlbum) -> some View {
        Button {
            guard !album.isEmpty else { return }
            HapticsManager.shared.trigger(.lightImpact)
            onSelect(album)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                AlbumCover(
                    album: album,
                    library: library,
                    isSelected: album.id == selectedAlbumID
                )

                Text(album.title)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 8)

                // An empty album is captioned rather than counted: "0" reads like a number you
                // could still tap into.
                Text(album.isEmpty ? "Empty" : album.count.formatted(.number.grouping(.automatic)))
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        // Hiding empty albums is what makes someone ask where one went. Dimmed and inert answers
        // that and still costs no wasted tap.
        .disabled(album.isEmpty)
        .opacity(album.isEmpty ? 0.38 : 1)
        .accessibilityLabel(album.isEmpty
            ? "\(album.title), empty"
            : "\(album.title), \(album.count) items")
    }
}

/// One album's cover: its newest photo, with a lime ring when it is the album on screen.
private struct AlbumCover: View {
    let album: ShareAlbum
    let library: SharePhotoLibrary
    let isSelected: Bool

    @State private var thumbnail: UIImage?

    var body: some View {
        Color.white.opacity(0.05)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else if album.isEmpty {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Color.customGray)
                }
            }
            .clipped()
            .overlay {
                if isSelected {
                    Rectangle().stroke(Color.ascendAccent, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .task(id: album.id) {
                guard !album.isEmpty else { return }
                thumbnail = await library.albumCoverThumbnail(albumID: album.id, size: 130)
            }
    }
}
