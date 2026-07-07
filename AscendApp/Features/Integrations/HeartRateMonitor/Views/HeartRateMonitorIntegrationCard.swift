import SwiftUI

/// Overview card for Bluetooth heart-rate monitors on the Integrations list.
/// The card stays an overview surface; pairing and device actions live in
/// the manage sheet, matching the Apple Health card pattern.
struct HeartRateMonitorIntegrationCard: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var monitor = HeartRateMonitorService.shared
    @State private var showingManageSheet = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        let style = IntegrationCardStyle(effectiveColorScheme: effectiveColorScheme)

        IntegrationCardShell(style: style) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.ascendAccent)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.ascendAccent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Heart Rate Monitor")
                        .font(.montserratSemiBold(size: 17))
                        .foregroundStyle(style.primaryText)

                    Text(statusLabel)
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(statusColor(style: style))
                }

                Spacer()

                headerAction(style: style)
            }

            IntegrationCardDescriptionSection(
                style: style,
                text: description
            )
        }
        .sheet(isPresented: $showingManageSheet) {
            HeartRateMonitorManageSheet(isPresented: $showingManageSheet)
        }
    }

    @ViewBuilder
    private func headerAction(style: IntegrationCardStyle) -> some View {
        if monitor.rememberedDevice == nil {
            IntegrationCardActionButton(
                "Connect",
                appearance: .filled(background: .accent, foreground: .black)
            ) {
                showingManageSheet = true
            }
        } else {
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

    private var statusLabel: String {
        if monitor.isConnected, let name = monitor.connectedDeviceName {
            return "Connected · \(name)"
        }
        if let remembered = monitor.rememberedDevice {
            return "Paired · \(remembered.name)"
        }
        return "Not connected"
    }

    private func statusColor(style: IntegrationCardStyle) -> Color {
        monitor.isConnected ? .ascendAccent : style.secondaryText
    }

    private var description: String {
        if monitor.rememberedDevice == nil {
            return "Pair a Bluetooth chest strap — Polar, Garmin, Morpheus, or any standard heart rate monitor — and see live heart rate and effort zones on every climb."
        }
        return "Your monitor connects automatically when you start a climb. Live heart rate and effort zones show in the session, and every workout keeps its heart rate history."
    }
}
