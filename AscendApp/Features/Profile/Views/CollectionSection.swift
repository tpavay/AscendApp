import SwiftUI

struct CollectionSection: View {
    let collection: ProfileCollectionSummary
    let mode: ProfileViewMode

    private var previewCards: [ProfileCollectionCardItem] {
        Array(collection.previewCards.prefix(3))
    }

    var body: some View {
        if collection.catalogCount > 0, !previewCards.isEmpty {
            ProfileCardSurfaceView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("COLLECTION")
                        .font(.montserratSemiBold(size: 11))
                        .tracking(1.2)
                        .foregroundStyle(Color.accentColor)

                    Text("\(collection.collectedCount) of \(collection.catalogCount) climbs collected")
                        .font(.montserratBold(size: 21))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    HStack(alignment: .top, spacing: 10) {
                        ForEach(previewCards) { item in
                            NavigationLink {
                                ClimbDetailView(climb: item.climb, analyticsEntryPoint: .unknown)
                            } label: {
                                CollectionPreviewCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accessibilityLabel(for: item))
                            .accessibilityHint("Open \(item.climb.name)")
                        }
                    }

                    NavigationLink {
                        CollectionGalleryPlaceholderView(totalCount: collection.catalogCount)
                    } label: {
                        Text("View all \(collection.catalogCount) climbs")
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func accessibilityLabel(for item: ProfileCollectionCardItem) -> String {
        if let claimedAt = item.claimedAt {
            return "\(item.climb.name), claimed \(ProfileDateFormatters.fullDate(claimedAt))"
        }

        return "\(item.climb.name), not collected"
    }
}

private struct CollectionPreviewCard: View {
    let item: ProfileCollectionCardItem

    private let cornerRadius: CGFloat = 9

    var body: some View {
        VStack(spacing: 7) {
            ClimbArtworkView(climb: item.climb, variant: .card)
                .aspectRatio(1.02, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(item.climb.name)
                .font(.montserratBold(size: 11))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(height: 28)
                .frame(maxWidth: .infinity)

            statusStrip
                .frame(height: 32)
        }
        .padding(7)
        .frame(maxWidth: .infinity)
        .background(ProfileVisualStyle.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animatedClimbCardBorder(
            colors: item.climb.tier.borderColors,
            shadowColor: item.climb.tier.shadowColor,
            cornerRadius: cornerRadius,
            lineWidth: 1,
            isEmphasized: item.climb.tier.usesEmphasizedBorderStyle,
            animationStyle: .ambient
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var statusStrip: some View {
        if let claimedAt = item.claimedAt {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text("Claimed \(ProfileDateFormatters.fullDate(claimedAt))")
                    .font(.montserratMedium(size: 9))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text("Climb")
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1)
                )
        }
    }
}

private struct CollectionGalleryPlaceholderView: View {
    let totalCount: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("COLLECTION")
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(.white)
                    .tracking(1.4)

                ProfileCardSurfaceView {
                    Text("Full collection grid is next. \(totalCount) launched climbs are available.")
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(ProfileVisualStyle.background.ignoresSafeArea())
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
