import SwiftUI

struct IdentityHeroSection: View {
    let snapshot: ProfileSnapshot
    let mode: ProfileViewMode
    let measurementSystem: MeasurementSystem

    private var demographicsLine: String? {
        ProfileIdentityFormatter.demographicsLine(
            for: snapshot.identity,
            measurementSystem: measurementSystem
        )
    }

    private var joinedText: String? {
        ProfileIdentityFormatter.joinedDateText(for: snapshot.identity.joinedAt)
    }

    var body: some View {
        VStack(spacing: 8) {
            ProfileTopBar(mode: mode)

            ProfileCardSurfaceView {
                HStack(spacing: 18) {
                    avatar

                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.identity.displayName)
                            .font(.montserratBold(size: 28))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)

                        if let demographicsLine {
                            Text(demographicsLine)
                                .font(.montserratRegular(size: 14))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }

                        if let joinedText {
                            Text(joinedText)
                                .font(.montserratMedium(size: 14))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1)
                        }

                        Text(ProfileIdentityFormatter.pullStatText(for: snapshot, mode: mode))
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }

                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(ProfileVisualStyle.background)
    }

    @ViewBuilder
    private var avatar: some View {
        if mode == .own {
            NavigationLink {
                EditProfileView()
            } label: {
                avatarImage
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile")
        } else {
            avatarImage
        }
    }

    private var avatarImage: some View {
        ProfileAvatarImageView(photoURL: snapshot.identity.photoURL, size: 88)
            .overlay(alignment: .bottomTrailing) {
                if mode == .own {
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
}
