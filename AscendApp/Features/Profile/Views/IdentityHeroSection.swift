import SwiftUI

struct IdentityHeroSection: View {
    let snapshot: ProfileSnapshot
    let identity: ResolvedUserIdentity

    private var locationLine: String? {
        ProfileIdentityFormatter.locationLine(for: snapshot.demographics)
    }

    private var joinedText: String? {
        ProfileIdentityFormatter.joinedDateText(
            for: snapshot.demographics.joinedAt
        )
    }

    var body: some View {
        HStack(spacing: 18) {
            avatar

            VStack(alignment: .leading, spacing: 5) {
                if let joinedText {
                    Text(joinedText)
                        .font(.montserratMedium(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(identity.displayName)
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .padding(.trailing, 42)

                if let locationLine {
                    Text(locationLine)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .overlay(alignment: .topTrailing) {
            profileActionButton
                .padding(.trailing, 10)
                .padding(.top, 4)
        }
        .background(ProfileVisualStyle.background)
    }

    @ViewBuilder
    private var profileActionButton: some View {
        NavigationLink {
            AccountView()
        } label: {
            Label("Settings", systemImage: "gearshape")
                .labelStyle(.iconOnly)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatar: some View {
        NavigationLink {
            EditProfileView()
        } label: {
            avatarImage
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit profile")
    }

    private var avatarImage: some View {
        ProfileAvatarImageView(photoURL: identity.photoURL, size: 88)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
    }
}
