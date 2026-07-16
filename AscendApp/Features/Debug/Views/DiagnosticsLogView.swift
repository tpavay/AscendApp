#if DEBUG
import SwiftUI
import UIKit

struct DiagnosticsLogView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var events = AppDiagnosticsRecorder.shared.recentEvents()
    @State private var sharePayload: DiagnosticsLogSharePayload?
    @State private var copyConfirmationText: String?

    private var foregroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard

                if events.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(events) { event in
                            eventCard(event)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .themedBackground()
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(item: $sharePayload) { payload in
            ActivityView(activityItems: [payload.text])
                .appSheetStyle(.fraction(0.52))
        }
        .overlay(alignment: .bottom) {
            if let copyConfirmationText {
                Text(copyConfirmationText)
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.ascendAccent)
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Refresh", action: reload)
                    Button("Share Export") {
                        sharePayload = DiagnosticsLogSharePayload(text: exportText())
                    }
                    .disabled(events.isEmpty)

                    Button("Copy Export") {
                        copyExport()
                    }
                    .disabled(events.isEmpty)

                    Button("Clear", role: .destructive) {
                        AppDiagnosticsRecorder.shared.clear()
                        reload()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statusPill(title: "\(events.count) events", color: .accent)
                Spacer()
                Text("Local")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text("Lifecycle and headphone-session breadcrumbs")
                .font(.montserratBold(size: 18))
                .foregroundStyle(foregroundColor)

            Text("This log persists locally across app restarts and mirrors key breadcrumbs to Crashlytics when telemetry collection is enabled.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !events.isEmpty {
                Button {
                    sharePayload = DiagnosticsLogSharePayload(text: exportText())
                } label: {
                    Label("Share Export", systemImage: "square.and.arrow.up")
                        .font(.montserratSemiBold(size: 13))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.ascendAccent)
                .accessibilityHidden(true)

            Text("No Diagnostics Yet")
                .font(.montserratBold(size: 20))
                .foregroundStyle(foregroundColor)

            Text("Use the app, background it, or start a headphone-tracked session, then come back here.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 48)
    }

    private func eventCard(_ event: AppDiagnosticEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                statusPill(title: event.level.rawValue.capitalized, color: color(for: event.level))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title(for: event.name))
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(foregroundColor)

                    Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !event.details.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(event.details.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(alignment: .top, spacing: 10) {
                            Text(key)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(foregroundColor.opacity(0.85))
                                .frame(width: 140, alignment: .leading)

                            Text(value)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Text(event.name)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.85))
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.montserratSemiBold(size: 11))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(0.14))
            )
    }

    private func color(for level: AppDiagnosticEvent.Level) -> Color {
        switch level {
        case .info:
            return .accent
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func title(for name: String) -> String {
        name
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func reload() {
        events = AppDiagnosticsRecorder.shared.recentEvents()
    }

    private func copyExport() {
        UIPasteboard.general.string = exportText()
        withAnimation(.smooth(duration: 0.2)) {
            copyConfirmationText = "Diagnostics copied"
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.smooth(duration: 0.2)) {
                copyConfirmationText = nil
            }
        }
    }

    private func exportText() -> String {
        let generatedAt = Date()
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = [
            "Ascend diagnostics export",
            "generated_at=\(formatter.string(from: generatedAt))",
            "app_version=\(version)",
            "build=\(build)",
            "system_name=\(UIDevice.current.systemName)",
            "system_version=\(UIDevice.current.systemVersion)",
            "device_model=\(UIDevice.current.model)",
            "event_count=\(events.count)",
            ""
        ]

        for event in events.reversed() {
            lines.append("[\(formatter.string(from: event.timestamp))] \(event.level.rawValue.uppercased()) \(event.name)")
            for (key, value) in event.details.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(key)=\(value)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

private struct DiagnosticsLogSharePayload: Identifiable {
    let id = UUID()
    let text: String
}
#endif
