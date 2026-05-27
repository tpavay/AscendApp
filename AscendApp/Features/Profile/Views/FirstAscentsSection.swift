import SwiftUI

struct FirstAscentsSection: View {
    let held: [ProfileFirstAscentSummary]
    let open: [ProfileFirstAscentSummary]
    let mode: ProfileViewMode
    let climbs: [Climb]

    private var climbsByID: [String: Climb] {
        Dictionary(uniqueKeysWithValues: climbs.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionHeaderView(title: "First Ascents", trailing: "\(held.count) claimed")

            ProfileCardSurfaceView {
                VStack(alignment: .leading, spacing: 12) {
                    if held.isEmpty {
                        emptyContent
                    } else {
                        heldContent
                    }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        HStack(spacing: 12) {
            firstAscentBadge(assetName: "FirstAscentBadgeDetailed", size: 58)

            Text("0 claimed")
                .font(.montserratBold(size: 24))
                .foregroundStyle(.white)
        }

        if open.isEmpty {
            Text("Every First Ascent is taken. New climbs drop monthly - turn on notifications to get 24 hours' notice.")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if mode == .own {
                Button("Turn on notifications") {}
                    .buttonStyle(ProfileActionButtonStyle())
                    .disabled(true)
                    .opacity(0.72)
            }
        } else {
            Text("\(open.count) First Ascents are still open. Be the first up.")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(ProfileVisualStyle.secondaryText)

            ForEach(open.prefix(3)) { ascent in
                firstAscentRow(ascent, isOpen: true)
            }
        }
    }

    private var heldContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                firstAscentBadge(assetName: "FirstAscentBadgeDetailed", size: 58)

                Text("\(held.count) claimed")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(.white)
            }

            ForEach(held.prefix(4)) { ascent in
                firstAscentRow(ascent, isOpen: false)
            }

            if !open.isEmpty {
                Text("\(open.count) more First Ascents still open.")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
            }
        }
    }

    private func firstAscentRow(_ ascent: ProfileFirstAscentSummary, isOpen: Bool) -> some View {
        let row = HStack(spacing: 10) {
            climbThumbnail(for: ascent)

            VStack(alignment: .leading, spacing: 4) {
                Text(ascent.climbName)
                    .font(.montserratBold(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text(subtitle(for: ascent))
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer()

            if isOpen {
                Text("Climb")
                    .font(.montserratBold(size: 11))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 1)
                    }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        return Group {
            if isOpen, let climb = climbsByID[ascent.climbId] {
                NavigationLink {
                    ClimbDetailView(climb: climb, analyticsEntryPoint: .unknown)
                } label: {
                    row
                }
                .buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    private func subtitle(for ascent: ProfileFirstAscentSummary) -> String {
        switch ascent.kind {
        case .held(let claimedAt):
            return "Claimed \(ProfileDateFormatters.shortDate(claimedAt))"
        case .open:
            return ascent.locationText
        }
    }

    @ViewBuilder
    private func climbThumbnail(for ascent: ProfileFirstAscentSummary) -> some View {
        if let climb = climbsByID[ascent.climbId] {
            ClimbArtworkView(climb: climb, variant: .thumb)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ProfileVisualStyle.gold.opacity(0.16))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ProfileVisualStyle.gold)
                }
        }
    }

    private func firstAscentBadge(assetName: String, size: CGFloat) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: ProfileVisualStyle.gold.opacity(0.24), radius: 8, y: 3)
            .accessibilityHidden(true)
    }
}
