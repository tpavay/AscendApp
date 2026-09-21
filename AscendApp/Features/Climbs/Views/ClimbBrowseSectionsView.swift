import SwiftUI

/// The browse sections of the sheet over the globe: Today's Climb, Browse by Steps,
/// All Climbs, and Coming Soon. Shared by the Home sheet and the Browse screen a
/// Climb Detail pushes, so both list the catalog the same way.
struct ClimbBrowseSectionsView: View {
    @Bindable var viewModel: GlobeViewModel
    @Binding var selectedStepTier: ClimbTier?
    var showsTodaysClimb = true
    let onOpenClimb: (Climb, LiveClimbAnalyticsEvent.EntryPoint) -> Void
    /// Called when a section asks for the whole list, which lives in the expanded sheet.
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if showsTodaysClimb, let dailyRecommendedClimb = viewModel.dailyRecommendedClimb {
                todaysClimbSection(dailyRecommendedClimb)
            }

            stepRangeSection
            allClimbsSection

            if !viewModel.comingSoonClimbs.isEmpty {
                comingSoonSection
            }
        }
    }

    // MARK: - Sections

    private func todaysClimbSection(_ climb: Climb) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ClimbBrowseSectionHeader(title: "Today's Climb")

            ClimbBrowseResultRow(
                climb: climb,
                isCompleted: viewModel.isCompleted(climb),
                isHighlighted: true
            ) {
                onOpenClimb(climb, .browseSection)
            }
        }
    }

    private var allClimbsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ClimbBrowseSectionHeader(title: allClimbsTitle)

                Spacer(minLength: 0)

                if selectedStepTier != nil {
                    Button {
                        withAnimation(.smooth(duration: 0.18)) {
                            selectedStepTier = nil
                        }
                    } label: {
                        Text("Clear")
                            .font(.montserratBold(size: 11))
                            .foregroundStyle(.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 8) {
                ForEach(displayedClimbs) { climb in
                    ClimbBrowseResultRow(
                        climb: climb,
                        isCompleted: viewModel.isCompleted(climb),
                        isHighlighted: climb.id == viewModel.dailyRecommendedClimb?.id
                    ) {
                        onOpenClimb(climb, .browseAll)
                    }
                }
            }
        }
    }

    private var stepRangeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClimbBrowseSectionHeader(title: "Browse by Steps")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(stepRangeBuckets, id: \.tier) { bucket in
                        stepRangeTile(
                            tier: bucket.tier,
                            count: bucket.count
                        )
                    }
                }
                .padding(.trailing, 2)
            }
        }
    }

    private func stepRangeTile(tier: ClimbTier, count: Int) -> some View {
        let isSelected = selectedStepTier == tier

        return Button {
            withAnimation(.smooth(duration: 0.18)) {
                selectedStepTier = isSelected ? nil : tier
            }
            onExpand()
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tier.color)
                        .frame(width: 8, height: 8)

                    Text(tier.displayName.uppercased())
                        .font(.montserratBold(size: 11))
                        .tracking(0.8)
                        .foregroundStyle(isSelected ? .black : .white)
                        .lineLimit(1)
                }

                Text(tier.stepRangeDescription)
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(isSelected ? .black.opacity(0.72) : .white.opacity(0.78))
                    .lineLimit(1)

                Text("\(count) \(count == 1 ? "climb" : "climbs")")
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(isSelected ? .black.opacity(0.55) : .white.opacity(0.48))
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: 152, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accent : .white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accent : tier.color.opacity(0.26), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tier.displayName), \(tier.stepRangeDescription), \(count) climbs")
    }

    private var comingSoonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClimbBrowseSectionHeader(title: "Coming Soon")

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.accent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(viewModel.comingSoonClimbs.count.formatted()) First Ascents are still locked.")
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("New climbs open soon. Ghost pins on the globe show where the next races will land.")
                        .font(.montserratRegular(size: 12.5))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Section data

    private var allClimbs: [Climb] {
        viewModel.availableClimbs.sorted { lhs, rhs in
            if lhs.referenceStepCount == rhs.referenceStepCount {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.referenceStepCount < rhs.referenceStepCount
        }
    }

    private var displayedClimbs: [Climb] {
        guard let selectedStepTier else {
            return allClimbs
        }

        return allClimbs.filter {
            ClimbTier(steps: $0.referenceStepCount) == selectedStepTier
        }
    }

    private var allClimbsTitle: String {
        if let selectedStepTier {
            return "\(selectedStepTier.stepRangeDescription) (\(displayedClimbs.count))"
        }

        return "All Climbs (\(allClimbs.count))"
    }

    private var stepRangeBuckets: [(tier: ClimbTier, count: Int)] {
        ClimbTier.allCases.compactMap { tier in
            let count = allClimbs.filter {
                ClimbTier(steps: $0.referenceStepCount) == tier
            }.count

            guard count > 0 else { return nil }
            return (tier, count)
        }
    }
}

/// The small tracked caption above a sheet section.
struct ClimbBrowseSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.montserratBold(size: 10))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.56))
            .lineLimit(1)
    }
}

/// One tappable climb row in a sheet list.
struct ClimbBrowseResultRow: View {
    let climb: Climb
    let isCompleted: Bool
    var isHighlighted = false
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ClimbResultRowView(
                climb: climb,
                isCompleted: isCompleted
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isHighlighted ? Color.accent.opacity(0.72) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(climb.name), \(climb.displayLocation)")
        .accessibilityHint("Open climb detail")
    }
}

/// The results of the sheet's climb search.
struct ClimbSearchResultsView: View {
    @Bindable var viewModel: GlobeViewModel
    let onOpenClimb: (Climb) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClimbBrowseSectionHeader(title: "Results")

            if viewModel.searchSuggestions.isEmpty {
                noSearchResultsView
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.searchSuggestions) { climb in
                        ClimbBrowseResultRow(
                            climb: climb,
                            isCompleted: viewModel.isCompleted(climb)
                        ) {
                            onOpenClimb(climb)
                        }
                    }
                }
            }
        }
    }

    private var noSearchResultsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No climbs found")
                .font(.montserratSemiBold(size: 15))
                .foregroundStyle(.white.opacity(0.86))

            Text("Try a landmark, city, country, or category.")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(.white.opacity(0.54))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}
