import SwiftUI

/// Pairing and device management for Bluetooth heart-rate monitors.
/// Scanning starts when the sheet appears (first appearance triggers the
/// system Bluetooth permission prompt) and stops when it disappears.
struct HeartRateMonitorManageSheet: View {
    @Binding var isPresented: Bool

    @State private var monitor = HeartRateMonitorService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.ascendAccent)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.ascendAccent.opacity(0.14))
                    )

                Text("Heart Rate Monitor")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(.white)

                Spacer()
            }

            Text("Live heart rate needs a Bluetooth chest strap. An Apple Watch can't stream live heart rate to Ascend, though it can add heart rate to a climb afterward through Apple Health.")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            content

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
        .onAppear {
            monitor.startPairingScan()
        }
        .onDisappear {
            monitor.stopPairingScan()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch monitor.availability {
        case .unauthorized:
            statusText(
                "Bluetooth access is off for Ascend. Allow it in Settings to connect your monitor.",
                actionTitle: "Open Settings",
                action: openAppSettings
            )
        case .poweredOff:
            statusText("Bluetooth is off. Turn it on in Control Center to connect your monitor.")
        case .unsupported:
            statusText("This device doesn't support Bluetooth heart rate monitors.")
        case .unknown, .poweredOn:
            deviceList
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        if monitor.isConnected, let name = monitor.connectedDeviceName {
            connectedDeviceRow(name: name)
        } else if let remembered = monitor.rememberedDevice {
            rememberedDeviceRow(remembered)
        }

        if monitor.didLastConnectAttemptTimeOut {
            statusText(
                "Couldn't reach the monitor. If it's connected to another device — a watch or gym console — disconnect it there first. Polar straps may need two-device mode enabled in the Polar app."
            )
        }

        scanSection
    }

    private func connectedDeviceRow(name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                liveReadout

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(.white)
                    Text("Connected")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(Color.ascendAccent)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button("Disconnect") {
                    monitor.disconnect()
                }
                .appSheetButtonStyle(tone: .subtle)

                Button("Forget Device") {
                    monitor.forgetDevice()
                }
                .appSheetButtonStyle(tone: .destructive)
            }
        }
        .padding(16)
        .appSheetCardStyle(tone: .standard)
    }

    private func rememberedDeviceRow(_ device: HeartRateMonitorService.RememberedDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)
                Text(rememberedDeviceStatusText)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Button("Forget") {
                monitor.forgetDevice()
            }
            .font(.montserratSemiBold(size: 13))
            .foregroundStyle(.white.opacity(0.6))
            .buttonStyle(.plain)
        }
        .padding(16)
        .appSheetCardStyle(tone: .standard)
    }

    private var rememberedDeviceStatusText: String {
        switch monitor.connectionState {
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .disconnected, .scanning, .connected, .failed:
            return "Paired · not in range"
        }
    }

    private var liveReadout: some View {
        VStack(spacing: 1) {
            Image(systemName: "heart.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.ascendAccent)
            Text(monitor.freshMeasurement.map { "\($0.beatsPerMinute)" } ?? "--")
                .font(.montserratBold(size: 14))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.ascendAccent.opacity(0.12))
        )
    }

    @ViewBuilder
    private var scanSection: some View {
        HStack(spacing: 8) {
            Text("NEARBY MONITORS")
                .font(.montserratBold(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .kerning(0.7)

            ProgressView()
                .controlSize(.mini)
                .tint(.white.opacity(0.5))

            Spacer()
        }

        let candidates = monitor.discoveredDevices.filter { $0.id != connectedCandidateID }
        if candidates.isEmpty {
            Text("Strap on your monitor to wake it up. Scanning...")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.55))
        } else {
            ForEach(candidates) { candidate in
                Button {
                    monitor.connect(to: candidate)
                } label: {
                    IntegrationManageActionRow(
                        action: IntegrationManageAction(
                            systemImage: "dot.radiowaves.left.and.right",
                            title: candidate.name,
                            iconTint: .accent,
                            badgeCount: 0,
                            isEnabled: true,
                            action: {}
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var connectedCandidateID: UUID? {
        guard monitor.isConnected else { return nil }
        return monitor.rememberedDevice?.id
    }

    private func statusText(
        _ text: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .appSheetButtonStyle(tone: .subtle)
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
