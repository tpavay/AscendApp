import SwiftUI

struct IdentityHeroSection: View {
    let snapshot: ProfileSnapshot
    let mode: ProfileViewMode

    private var locationLine: String? {
        ProfileIdentityFormatter.locationLine(for: snapshot.identity)
    }

    private var joinedText: String? {
        ProfileIdentityFormatter.joinedDateText(for: snapshot.identity.joinedAt)
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

                Text(snapshot.identity.displayName)
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
        if mode == .own {
            NavigationLink {
                AccountView()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Menu("Profile actions", systemImage: "ellipsis") {
                Button("Report", systemImage: "flag") {}
                    .disabled(true)
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white.opacity(0.86))
            .frame(width: 38, height: 38)
        }
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
