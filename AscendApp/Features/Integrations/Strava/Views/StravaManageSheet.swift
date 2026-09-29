import SwiftUI

/// Where a connected climber sees what the connection does and ends it.
/// Strava's API Policy asks for a clear route to the athlete's own Strava
/// account and a plain statement of what disconnecting deletes.
struct StravaManageSheet: View {
    @Environment(\.openURL) private var openURL

    let viewModel: StravaIntegrationViewModel
    @Binding var isPresented: Bool

    private static let stravaAppsSettingsURL = URL(string: "https://www.strava.com/settings/apps")!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                StravaIntegrationGlyph(size: 38, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Strava")
                        .font(.montserratBold(size: 20))
                        .foregroundStyle(.white)

                    if let statusLabel = viewModel.statusLabel {
                        Text(statusLabel)
                            .font(.montserratMedium(size: 13))
                            .foregroundStyle(Color.ascendAccent)
                    }
                }

                Spacer()
            }

            Text("Climbs you finish go to Strava about 15 minutes later, once heart rate has had time to arrive. Disconnect to stop: Ascend revokes its Strava access and deletes everything it holds from Strava.")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openURL(Self.stravaAppsSettingsURL)
            } label: {
                IntegrationManageActionRow(
                    action: IntegrationManageAction(
                        systemImage: "safari",
                        title: "View on Strava",
                        iconTint: .accent,
                        badgeCount: 0,
                        isEnabled: true,
                        action: {}
                    )
                )
            }
            .buttonStyle(.plain)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    await viewModel.disconnect()
                    if !viewModel.status.isConnected {
                        isPresented = false
                    }
                }
            } label: {
                if viewModel.isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Disconnect Strava")
                }
            }
            .appSheetButtonStyle(tone: .destructive)
            .disabled(viewModel.isWorking)

            Button("Close") {
                isPresented = false
            }
            .appSheetButtonStyle(tone: .subtle)
        }
        .padding(.top, 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .appSheetBackground()
        .appSheetStyle(.actionMenu)
        .onDisappear {
            viewModel.errorMessage = nil
        }
        .trackOnce(screen: .stravaManage)
    }
}
