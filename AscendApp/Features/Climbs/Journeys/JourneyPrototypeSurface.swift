#if DEBUG
import SwiftData
import SwiftUI

struct JourneyPrototypeSurface: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = GlobeViewModel()
    @State private var selectedJourneyId: String?
    @State private var highlightedClimbId: String?
    @State private var detailClimb: Climb?
    @State private var previewProgressEnabled = true
    @State private var didLoad = false

    private var journeys: [JourneyPrototype] {
        JourneyPrototypeBuilder.makeJourneys(from: viewModel.visibleClimbs)
    }

    private var selectedJourney: JourneyPrototype? {
        journeys.first { $0.id == selectedJourneyId } ?? journeys.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let loadErrorMessage = viewModel.loadErrorMessage {
                    errorState(loadErrorMessage)
                } else if journeys.isEmpty {
                    emptyState
                } else {
                    selectorSection

                    if let selectedJourney {
                        journeyDetail(selectedJourney)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Journey Prototype")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $detailClimb) { climb in
            ClimbDetailView(
                climb: climb,
                showsBrowseBackButton: true,
                analyticsEntryPoint: .unknown
            )
        }
        .task {
            loadIfNeeded()
        }
        .onChange(of: selectedJourney?.id) { _, _ in
            highlightedClimbId = selectedJourney?.nextClimb(in: completedIds(for: selectedJourney))?.id
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DEBUG PROTOTYPE")
                .font(.montserratBold(size: 11))
                .tracking(1.8)
                .foregroundStyle(Color.accent)

            Text("Circuits")
                .font(.montserratBold(size: 34))
                .foregroundStyle(.white)

            Text("Complete the current climb. Unlock the next. Finish the chain.")
                .font(.montserratMedium(size: 15))
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Preview progress", isOn: $previewProgressEnabled)
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(.white.opacity(0.82))
                .tint(Color.accent)
                .padding(.top, 4)
        }
    }

    private var selectorSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(journeys) { journey in
                    Button {
                        selectedJourneyId = journey.id
                        highlightedClimbId = journey.nextClimb(in: completedIds(for: journey))?.id
                    } label: {
                        JourneySelectorCard(
                            journey: journey,
                            completedClimbIds: completedIds(for: journey),
                            isSelected: selectedJourney?.id == journey.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func journeyDetail(_ journey: JourneyPrototype) -> some View {
        let completedIds = completedIds(for: journey)

        return VStack(alignment: .leading, spacing: 16) {
            JourneyRouteMapPreview(
                journey: journey,
                completedClimbIds: completedIds,
                selectedClimbId: highlightedClimbId,
                onSelectClimb: { climb in
                    highlightedClimbId = climb.id
                }
            )

            journeyStats(journey, completedIds: completedIds)

            nextClimbPanel(journey, completedIds: completedIds)

            JourneyProgressRailView(
                journey: journey,
                completedClimbIds: completedIds,
                selectedClimbId: highlightedClimbId,
                onSelectClimb: { climb in
                    highlightedClimbId = climb.id
                }
            )

            rewardPanel(journey)
        }
    }

    private func journeyStats(_ journey: JourneyPrototype, completedIds: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(journey.title)
                        .font(.montserratBold(size: 24))
                        .foregroundStyle(.white)

                    Text(journey.subtitle.uppercased())
                        .font(.montserratSemiBold(size: 11))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Text(journey.progressText(in: completedIds))
                    .font(.montserratBold(size: 13))
                    .foregroundStyle(.black.opacity(0.86))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(journey.accent, in: Capsule())
            }

            Text(journey.thesis)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                statBox(title: "Climbs", value: journey.climbs.count.formatted())
                statBox(title: "Steps", value: journey.totalSteps.formatted())
                statBox(title: "Next", value: journey.nextClimb(in: completedIds)?.tier.rawValue.uppercased() ?? "DONE")
            }
        }
        .padding(15)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func nextClimbPanel(_ journey: JourneyPrototype, completedIds: Set<String>) -> some View {
        Group {
            if let nextClimb = journey.nextClimb(in: completedIds) {
                Button {
                    detailClimb = nextClimb
                } label: {
                    HStack(spacing: 12) {
                        ClimbArtworkView(climb: nextClimb, variant: .thumb)
                            .frame(width: 82, height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("NEXT CLIMB")
                                .font(.montserratBold(size: 10))
                                .tracking(1.5)
                                .foregroundStyle(journey.accent)

                            Text(nextClimb.name)
                                .font(.montserratBold(size: 19))
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            Text(nextClimb.displayLocation)
                                .font(.montserratMedium(size: 12))
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.74))
                    }
                    .padding(12)
                    .background(journey.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(journey.accent.opacity(0.42), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(journey.accent)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("CIRCUIT COMPLETE")
                            .font(.montserratBold(size: 10))
                            .tracking(1.5)
                            .foregroundStyle(journey.accent)

                        Text("Every climb in this chain is claimed.")
                            .font(.montserratBold(size: 17))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(journey.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(journey.accent.opacity(0.36), lineWidth: 1)
                }
            }
        }
    }

    private func rewardPanel(_ journey: JourneyPrototype) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(journey.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text("FINISH REWARD")
                    .font(.montserratBold(size: 10))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.48))

                Text(journey.reward)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func statBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.montserratSemiBold(size: 9))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.42))

            Text(value)
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No circuits loaded.")
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)

            Text("Load the climb catalog to build debug circuits.")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Catalog failed.")
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)

            Text(message)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }

    private func completedIds(for journey: JourneyPrototype?) -> Set<String> {
        guard previewProgressEnabled, let journey else {
            return viewModel.completedClimbIds
        }

        return viewModel.completedClimbIds.union(journey.climbs.prefix(2).map(\.id))
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        viewModel.loadIfNeeded(modelContext: modelContext)

        if let firstJourney = journeys.first {
            selectedJourneyId = firstJourney.id
            highlightedClimbId = firstJourney.nextClimb(in: completedIds(for: firstJourney))?.id
        }
    }
}
#endif
