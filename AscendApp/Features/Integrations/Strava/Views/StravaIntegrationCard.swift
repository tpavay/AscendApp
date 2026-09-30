import SwiftUI

/// Overview card for Strava on the Integrations list. Connecting happens here
/// through Strava's own "Connect with Strava" button, which its brand
/// guidelines require; disconnecting lives in the manage sheet.
struct StravaIntegrationCard: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var showingManageSheet = false

    let viewModel: StravaIntegrationViewModel

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        let style = IntegrationCardStyle(effectiveColorScheme: effectiveColorScheme)

        IntegrationCardShell(style: style) {
            HStack(spacing: 12) {
                StravaIntegrationGlyph(size: 44, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Strava")
                        .font(.montserratSemiBold(size: 17))
                        .foregroundStyle(style.primaryText)

                    Text(viewModel.statusLabel ?? "Not connected")
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(viewModel.status.isConnected ? Color.ascendAccent : style.secondaryText)
                }

                Spacer()

                if viewModel.status.isConnected {
                    IntegrationCardActionButton(
                        "Manage",
                        appearance: .outlined(
                            foreground: style.subtleActionText,
                            border: style.subtleActionBorder
                        )
                    ) {
                        showingManageSheet = true
                    }
                }
            }

            IntegrationCardDescriptionSection(style: style, text: viewModel.description)

            if !viewModel.status.isConnected {
                ConnectWithStravaButton(isWorking: viewModel.isWorking) {
                    Task { await viewModel.connect() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showingManageSheet) {
            StravaManageSheet(viewModel: viewModel, isPresented: $showingManageSheet)
        }
        .alert("Strava", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && !showingManageSheet },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}
