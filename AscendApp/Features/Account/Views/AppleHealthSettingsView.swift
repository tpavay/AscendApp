import SwiftUI
import UIKit

/// Settings -> Apple Health: whether Health is connected, whether new stair stepper workouts
/// import on their own, and the way to bring in the ones from before the climber joined.
///
/// Settings itself carries one disclosure row to here and no state, like every other row on it.
/// Off, this screen is the one row that opens the Connect flow. iOS gives an app no way to
/// disconnect Health, so the connected row says where access is managed and opens the Health app.
struct AppleHealthSettingsView: View {
    @State private var importService: AppleHealthImportService
    @State private var showingConnectFlow = false
    @State private var showingOlderWorkouts = false
    private let openHealthApp: () -> Void

    init(
        importService: AppleHealthImportService = .shared,
        openHealthApp: @escaping () -> Void = {
            guard let url = URL(string: "x-apple-health://") else { return }
            UIApplication.shared.open(url)
        }
    ) {
        _importService = State(initialValue: importService)
        self.openHealthApp = openHealthApp
    }

    static let connectedDetail = "Connected. Manage access in the Health app."
    static let offDetail = "Off. Connect to import stair stepper workouts."
    static let autoImportDetail = "New stair stepper workouts become climbs on their own."
    static let olderWorkoutsDetail = "Add the ones from before you joined to your history."
    static let notOfferedDetail = "Apple Health import is not available right now."

    /// Whether Settings shows the row that leads here: import is on offer on this device.
    static func isOffered(by importService: AppleHealthImportService) -> Bool {
        guard let connection = importService.offeredImportConnectionState else { return false }
        return connection != .unavailable
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if Self.isOffered(by: importService) {
                    let isConnected = importService.offeredImportConnectionState == .connected

                    ProfileSection(title: "Connection") {
                        ProfileCardSurface {
                            connectionRow(isConnected: isConnected)
                        }
                    }

                    if isConnected {
                        ProfileSection(title: "Import") {
                            ProfileCardSurface {
                                VStack(spacing: 0) {
                                    autoImportRow

                                    if importService.offersOlderWorkouts {
                                        ProfileCardDivider()
                                        olderWorkoutsRow
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // The kill switch can be thrown while this screen is open.
                    Text(Self.notOfferedDetail)
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .themedBackground()
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingConnectFlow) {
            AppleHealthConnectFlowView(
                importService: importService,
                onFinished: { showingConnectFlow = false },
                onClose: { showingConnectFlow = false }
            )
        }
        .fullScreenCover(isPresented: $showingOlderWorkouts) {
            AppleHealthOlderWorkoutsView(
                viewModel: AppleHealthOlderWorkoutsViewModel(importService: importService),
                onClose: { showingOlderWorkouts = false }
            )
        }
        .trackOnce(screen: .appleHealthSettings)
    }

    private func connectionRow(isConnected: Bool) -> some View {
        Button {
            if isConnected {
                openHealthApp()
            } else {
                showingConnectFlow = true
            }
        } label: {
            row(title: "Apple Health", detail: isConnected ? Self.connectedDetail : Self.offDetail) {
                Image("appleHealth-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 7))
            }
        }
        .buttonStyle(.plain)
    }

    private var olderWorkoutsRow: some View {
        Button {
            showingOlderWorkouts = true
        } label: {
            row(title: "Import older workouts", detail: Self.olderWorkoutsDetail) {
                AppIcon(token: .settingsHealthOlderWorkouts, pointSize: 22, weight: .medium)
                    .foregroundStyle(.accent)
            }
        }
        .buttonStyle(.plain)
    }

    /// The label is part of the control, so the whole row is one target and one VoiceOver element.
    private var autoImportRow: some View {
        Toggle(isOn: Binding(
            get: { importService.isAutoImportEnabled },
            set: { isEnabled in
                Task { await importService.setAutoImportEnabled(isEnabled) }
            }
        )) {
            HStack(spacing: 16) {
                AppIcon(token: .settingsHealthAutoImport, pointSize: 22, weight: .medium)
                    .foregroundStyle(.accent)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                rowText(title: "Import automatically", detail: Self.autoImportDetail)
            }
        }
        .toggleStyle(.switch)
        .tint(.accent)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(minHeight: 44)
    }

    /// A row that goes somewhere: icon, title over a line of detail, and the disclosure chevron.
    private func row<Icon: View>(
        title: String,
        detail: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 16) {
            icon()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            rowText(title: title, detail: detail)

            Spacer(minLength: 12)

            AppIcon(token: .disclosureChevronRight, pointSize: 14, weight: .medium)
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func rowText(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(.white)

            Text(detail)
                .font(.montserratRegular(size: 13))
                .foregroundStyle(.white.opacity(0.64))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
