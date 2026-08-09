#if DEBUG
import SwiftUI

struct TelemetryConsoleView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all
        case analytics
        case breadcrumb
        case screen

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                "All"
            case .analytics:
                "Analytics"
            case .breadcrumb:
                "Breadcrumbs"
            case .screen:
                "Screens"
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var store = DebugTelemetryConsoleStore.shared
    @State private var selectedFilter: Filter = .all
    @State private var selectedEntry: DebugTelemetryConsoleEntry?

    private var foregroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var filteredEntries: [DebugTelemetryConsoleEntry] {
        switch selectedFilter {
        case .all:
            return store.entries
        case .analytics:
            return store.entries.filter { $0.kind == .analytics }
        case .breadcrumb:
            return store.entries.filter { $0.kind == .breadcrumb }
        case .screen:
            return store.entries.filter { $0.kind == .screen }
        }
    }

    private var analyticsCount: Int {
        store.entries.filter { $0.kind == .analytics }.count
    }

    private var breadcrumbCount: Int {
        store.entries.filter { $0.kind == .breadcrumb }.count
    }

    private var screenCount: Int {
        store.entries.filter { $0.kind == .screen }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusCard
                filterPicker

                if filteredEntries.isEmpty {
                    emptyState
                } else {
                    entriesSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .themedBackground()
        .navigationTitle("Telemetry Console")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEntry) { entry in
            TelemetryConsoleEntryInfoSheet(entry: entry)
                .appSheetStyle(.fraction(0.68))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    store.clear()
                }
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.accent)
                .disabled(filteredEntries.isEmpty)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                statusPill(
                    title: store.isCollectionEnabled ? "Telemetry On" : "Telemetry Off",
                    color: store.isCollectionEnabled ? .green : .orange
                )

                Spacer()

                Text("\(store.entries.count) entries")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                countPill(title: "Analytics \(analyticsCount)", color: .accent)
                countPill(title: "Breadcrumbs \(breadcrumbCount)", color: .orange)
                countPill(title: "Screens \(screenCount)", color: .blue)
            }

            Text(
                store.isCollectionEnabled
                    ? "Analytics are product events, breadcrumbs are crash-tracing checkpoints, and screens are view opens. Tap the info icon on any row for a plain-English explanation."
                    : "Telemetry is disabled for this run. Launch Debug once with `-TelemetryEnabled` or `ASC_DEBUG_TELEMETRY_ENABLED=1`; that setting sticks for later Debug launches."
            )
            .font(.montserratRegular(size: 14))
            .foregroundStyle(.secondary)

            if let userID = store.currentUserID, !userID.isEmpty {
                Text("Current User ID: \(userID)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(foregroundColor.opacity(0.8))
            }

            Button {
                sendMixpanelProbe()
            } label: {
                Label("Send Mixpanel Probe", systemImage: "paperplane.fill")
                    .font(.montserratSemiBold(size: 13))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!store.isCollectionEnabled)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var filterPicker: some View {
        Picker("Telemetry Type", selection: $selectedFilter) {
            ForEach(Filter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 42))
                .foregroundStyle(.accent)

            Text(emptyStateTitle)
                .font(.montserratBold(size: 20))
                .foregroundStyle(foregroundColor)

            Text(emptyStateMessage)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 48)
    }

    private var emptyStateTitle: String {
        switch selectedFilter {
        case .all:
            return "No Telemetry Yet"
        case .analytics:
            return "No Analytics Events Yet"
        case .breadcrumb:
            return "No Breadcrumbs Yet"
        case .screen:
            return "No Screen Views Yet"
        }
    }

    private var emptyStateMessage: String {
        if !store.isCollectionEnabled {
            return "Launch Debug once with `-TelemetryEnabled` or `ASC_DEBUG_TELEMETRY_ENABLED=1`, then restart and use the app."
        }

        switch selectedFilter {
        case .all:
            return "Use the app for a moment, then come back here to inspect emitted telemetry."
        case .analytics:
            return "Open a flow that has product analytics wired up, like a Live Climb, to see analytics events here."
        case .breadcrumb:
            return "Breadcrumbs appear for tracked app flows such as auth, live climbs, and sync."
        case .screen:
            return "Open a screen with manual screen tracking, like a climb detail, to see screen views here."
        }
    }

    private var entriesSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredEntries) { entry in
                entryCard(entry)
            }
        }
    }

    private func entryCard(_ entry: DebugTelemetryConsoleEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                statusPill(
                    title: entry.kind.displayName,
                    color: pillColor(for: entry.kind)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(foregroundColor)

                    HStack(spacing: 8) {
                        Text(entry.feature)
                            .font(.montserratMedium(size: 12))
                            .foregroundStyle(.secondary)

                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 4, height: 4)

                        Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                            .font(.montserratRegular(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    selectedEntry = entry
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.accent.opacity(0.9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Explain \(entry.title)")
            }

            Text(entry.summary)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                detailChip(title: entry.destinationsSummary, color: .secondary)

                if let environment = entry.environment {
                    detailChip(title: environment, color: .accent)
                }
            }

            if !entry.parameters.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Details")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(.secondary)

                    ForEach(entry.parameters) { parameter in
                        HStack(alignment: .top, spacing: 10) {
                            Text(parameter.key)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(foregroundColor.opacity(0.85))
                                .frame(width: 160, alignment: .leading)

                            Text(parameter.value)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Text("Internal name: \(entry.rawName)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
        )
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

    private func countPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.montserratSemiBold(size: 11))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    private func detailChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.montserratMedium(size: 11))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    private func pillColor(for kind: DebugTelemetryConsoleEntry.Kind) -> Color {
        switch kind {
        case .analytics:
            return .accent
        case .breadcrumb:
            return .orange
        case .screen:
            return .blue
        }
    }

    private func sendMixpanelProbe() {
        TelemetryManager.shared.track(
            TelemetryRecord(
                name: "debug_mixpanel_probe_sent",
                parameters: [
                    "probe_id": .string(UUID().uuidString),
                    "source": .string("telemetry_console"),
                    "sent_at_unix": .int(Int(Date().timeIntervalSince1970))
                ],
                destinations: [.analytics]
            )
        )
        selectedFilter = .analytics
    }
}
#endif
