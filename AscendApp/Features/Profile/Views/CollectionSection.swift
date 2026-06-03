import SwiftUI
import UIKit
import UserNotifications

struct CollectionSection: View {
    let collection: ProfileCollectionSummary
    let mode: ProfileViewMode

    private var previewCards: [ProfileCollectionCardItem] {
        Array(collection.previewCards.prefix(3))
    }

    var body: some View {
        if collection.catalogCount > 0, !previewCards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ProfileSectionHeaderView(
                    title: "Climbs Collection",
                    trailing: "\(collection.collectedCount) of \(collection.catalogCount)"
                )
                .accessibilityLabel("\(collection.collectedCount) of \(collection.catalogCount) climbs collected")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(previewCards) { item in
                            NavigationLink {
                                ClimbDetailView(climb: item.climb, analyticsEntryPoint: .unknown)
                            } label: {
                                CollectionCard(item: item, style: .profilePreview)
                                    .frame(width: CollectionCardStyle.profilePreview.cardWidth)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accessibilityLabel(for: item))
                            .accessibilityHint("Open \(item.climb.name)")
                        }

                        NavigationLink {
                            ClimbsCollectionView(collection: collection, mode: mode)
                        } label: {
                            ViewAllClimbsCard(catalogCount: collection.catalogCount)
                                .frame(width: CollectionCardStyle.profilePreview.cardWidth)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View all climbs")
                    }
                    .padding(.vertical, 1)
                    .padding(.trailing, 2)
                }
                .scrollIndicators(.hidden)
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

private struct ClimbsCollectionView: View {
    let collection: ProfileCollectionSummary
    let mode: ProfileViewMode

    @Environment(\.dismiss) private var dismiss
    @State private var selectedComingSoonClimb: Climb?
    @State private var isHandlingNotifications = false

    private let launchedColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    private let comingSoonColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topBar
                progressSummary
                launchedGrid

                if !collection.comingSoonClimbs.isEmpty {
                    comingSoonSection
                }

                if mode == .own {
                    notificationsCTA
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(ProfileVisualStyle.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedComingSoonClimb) { climb in
            CollectionComingSoonDetailSheet(climb: climb)
        }
    }

    private var topBar: some View {
        ZStack {
            Text("CLIMBS COLLECTION")
                .font(.montserratSemiBold(size: 18))
                .tracking(2.4)
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.045))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer(minLength: 0)
            }
        }
    }

    private var progressSummary: some View {
        HStack(spacing: 16) {
            CollectionProgressBar(
                collectedCount: collection.collectedCount,
                catalogCount: collection.catalogCount
            )
            .frame(height: 10)

            Text("\(collection.collectedCount) / \(collection.catalogCount)")
                .font(.montserratBold(size: 18))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collection.collectedCount) of \(collection.catalogCount) climbs collected")
    }

    private var launchedGrid: some View {
        LazyVGrid(columns: launchedColumns, spacing: 12) {
            ForEach(collection.launchedCards) { item in
                NavigationLink {
                    ClimbDetailView(climb: item.climb, analyticsEntryPoint: .unknown)
                } label: {
                    CollectionCard(item: item, style: .grid)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: item))
                .accessibilityHint("Open \(item.climb.name)")
            }
        }
    }

    private var comingSoonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COMING SOON")
                    .font(.montserratSemiBold(size: 11))
                    .tracking(2.4)
                    .foregroundStyle(Color.accentColor)

                Text("More climbs are on the way")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(.white)
            }

            LazyVGrid(columns: comingSoonColumns, spacing: 8) {
                ForEach(collection.comingSoonClimbs) { climb in
                    Button {
                        selectedComingSoonClimb = climb
                    } label: {
                        CollectionComingSoonCard(climb: climb)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Coming soon climb")
                    .accessibilityHint("Reveal the region")
                }
            }
        }
        .padding(.top, 2)
    }

    private var notificationsCTA: some View {
        VStack(spacing: 10) {
            Text("Be the first to know when new climbs drop.")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button {
                handleNotificationsTap()
            } label: {
                Text("Turn on notifications")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isHandlingNotifications)
        }
        .padding(.top, 2)
    }

    private func accessibilityLabel(for item: ProfileCollectionCardItem) -> String {
        if item.claimedAt != nil {
            return "\(item.climb.name), collected"
        }

        return "\(item.climb.name), not collected"
    }

    private func handleNotificationsTap() {
        guard !isHandlingNotifications else { return }
        isHandlingNotifications = true

        Task {
            await CollectionNotificationPermissionHandler.handleTurnOnNotifications(
                collection: collection
            )
            isHandlingNotifications = false
        }
    }
}

private struct CollectionProgressBar: View {
    let collectedCount: Int
    let catalogCount: Int

    private var progress: CGFloat {
        guard catalogCount > 0 else { return 0 }
        return min(max(CGFloat(collectedCount) / CGFloat(catalogCount), 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(proxy.size.width * progress, progress > 0 ? 18 : 0))
            }
        }
    }
}

private struct CollectionCardStyle {
    let cardWidth: CGFloat
    let artworkHeight: CGFloat
    let cardPadding: CGFloat
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let artworkCornerRadius: CGFloat
    let nameFontSize: CGFloat
    let nameHeight: CGFloat
    let buttonFontSize: CGFloat
    let buttonHeight: CGFloat
    let badgeSize: CGFloat

    var cardHeight: CGFloat {
        artworkHeight + nameHeight + buttonHeight + (spacing * 2) + (cardPadding * 2)
    }

    static let profilePreview = CollectionCardStyle(
        cardWidth: 154,
        artworkHeight: 138,
        cardPadding: 7,
        spacing: 7,
        cornerRadius: 9,
        artworkCornerRadius: 7,
        nameFontSize: 11,
        nameHeight: 28,
        buttonFontSize: 13,
        buttonHeight: 32,
        badgeSize: 26
    )

    static let grid = CollectionCardStyle(
        cardWidth: 0,
        artworkHeight: 96,
        cardPadding: 7,
        spacing: 7,
        cornerRadius: 10,
        artworkCornerRadius: 8,
        nameFontSize: 12,
        nameHeight: 30,
        buttonFontSize: 13,
        buttonHeight: 32,
        badgeSize: 26
    )
}

private struct ViewAllClimbsCard: View {
    let catalogCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "arrow.right")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("View all climbs")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text("\(catalogCount) climbs")
                    .font(.montserratSemiBold(size: 11))
                    .tracking(0.6)
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CollectionCardStyle.profilePreview.cardHeight)
        .background(Color.black.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: CollectionCardStyle.profilePreview.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CollectionCardStyle.profilePreview.cornerRadius, style: .continuous)
                .stroke(Color.accentColor.opacity(0.72), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: CollectionCardStyle.profilePreview.cornerRadius, style: .continuous))
    }
}

private struct CollectionCard: View {
    let item: ProfileCollectionCardItem
    let style: CollectionCardStyle

    private var isClaimed: Bool {
        item.claimedAt != nil
    }

    var body: some View {
        VStack(spacing: style.spacing) {
            ClimbArtworkView(climb: item.climb, variant: .card)
                .frame(height: style.artworkHeight)
                .saturation(isClaimed ? 1 : 0)
                .brightness(isClaimed ? 0 : -0.08)
                .clipShape(RoundedRectangle(cornerRadius: style.artworkCornerRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if isClaimed {
                        claimedBadge
                            .padding(7)
                    }
                }

            Text(item.climb.name)
                .font(.montserratBold(size: style.nameFontSize))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(height: style.nameHeight)
                .frame(maxWidth: .infinity)

            climbAction
        }
        .padding(style.cardPadding)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .animatedClimbCardBorder(
            colors: item.climb.tier.borderColors,
            shadowColor: item.climb.tier.shadowColor,
            cornerRadius: style.cornerRadius,
            lineWidth: 1,
            isEmphasized: item.climb.tier.usesEmphasizedBorderStyle,
            animationStyle: .static
        )
        .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }

    private var claimedBadge: some View {
        Circle()
            .fill(item.climb.tier.color)
            .frame(width: style.badgeSize, height: style.badgeSize)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: style.badgeSize * 0.48, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.88))
            }
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
            }
            .shadow(color: item.climb.tier.color.opacity(0.4), radius: 5, x: 0, y: 2)
    }

    private var climbAction: some View {
        Text("Climb")
            .font(.montserratSemiBold(size: style.buttonFontSize))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: style.buttonHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 1)
            )
    }
}

private struct CollectionComingSoonCard: View {
    let climb: Climb

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ClimbArtworkView(climb: climb, variant: .card)
                    .frame(height: 76)
                    .blur(radius: 8)
                    .saturation(0.25)
                    .brightness(-0.12)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("???")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.white)
                    .padding(.top, 30)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .bold))

                Text("Coming soon")
                    .font(.montserratSemiBold(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(.white)
        }
        .padding(7)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
        .opacity(0.42)
    }
}

private struct CollectionComingSoonDetailSheet: View {
    let climb: Climb
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .topTrailing) {
                ClimbArtworkView(climb: climb, variant: .hero)
                    .frame(height: 230)
                    .blur(radius: 12)
                    .saturation(0.18)
                    .brightness(-0.16)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.76)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    )

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.black.opacity(0.46)))
                }
                .buttonStyle(.plain)
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("???")
                    .font(.montserratBold(size: 30))
                    .foregroundStyle(.white)

                Text("Coming soon · \(climb.continent)")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(Color.accentColor)

                Text("New First Ascent slot loading. Watch the globe and be ready.")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(ProfileVisualStyle.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

@MainActor
private enum CollectionNotificationPermissionHandler {
    static func handleTurnOnNotifications(collection: ProfileCollectionSummary) async {
        let availableClimbs = collection.launchedCards.map(\.climb)
        let completedClimbIds = Set(
            collection.launchedCards.compactMap { item in
                item.claimedAt == nil ? nil : item.climb.id
            }
        )

        await TodayClimbNotificationPermissionController.enable(
            availableClimbs: availableClimbs,
            completedClimbIds: completedClimbIds
        )
    }
}
