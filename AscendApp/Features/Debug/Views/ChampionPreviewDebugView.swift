import SwiftUI

#if DEBUG
/// Lets a Dev build show every recap variant and the climber's own crowns without waiting
/// for a period to close. Nothing here writes to Firestore: crowns are applied to this
/// device's registry until the next refresh, and recaps are sample stories.
struct ChampionPreviewDebugView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(ChampionRegistry.self) private var championRegistry

    @State private var crownedTitles: Set<ChampionTitle> = []
    @State private var presentedStory: PeriodRecapStory?

    private var fixtures: ChampionRecapFixtures {
        ChampionRecapFixtures(
            viewerId: authVM.user?.uid ?? "debug-viewer",
            viewerName: authVM.displayName.isEmpty ? "Tyler Pavay" : authVM.displayName
        )
    }

    var body: some View {
        List {
            Section {
                ForEach(ChampionTitle.allCases, id: \.self) { title in
                    Toggle(isOn: binding(for: title)) {
                        Label("\(title.rawValue.capitalized) champion", image: title.crownAssetName)
                    }
                }
                Button("Restore live champions") {
                    crownedTitles = []
                    Task { await championRegistry.refresh() }
                }
            } header: {
                Text("Crown me on this device")
            } footer: {
                Text("Applies to this phone until the next refresh. Visit Profile, Settings and the boards to see the crown.")
            }

            Section("Recap") {
                ForEach(ChampionRecapFixtures.Variant.allCases) { variant in
                    Button(variant.rawValue) {
                        presentedStory = fixtures.story(variant)
                    }
                }
            }
        }
        .navigationTitle("Champions & Recap")
        .fullScreenCover(item: $presentedStory) { story in
            PeriodRecapView(story: story, viewerId: authVM.user?.uid) { _ in
                presentedStory = nil
            }
        }
    }

    private func binding(for title: ChampionTitle) -> Binding<Bool> {
        Binding(
            get: { crownedTitles.contains(title) },
            set: { isOn in
                if isOn {
                    crownedTitles.insert(title)
                } else {
                    crownedTitles.remove(title)
                }
                championRegistry.apply(fixtures.reigns(crowning: crownedTitles))
            }
        )
    }
}
#endif
