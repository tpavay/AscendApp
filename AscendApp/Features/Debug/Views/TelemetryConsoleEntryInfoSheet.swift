#if DEBUG
import SwiftUI

struct TelemetryConsoleEntryInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let entry: DebugTelemetryConsoleEntry

    private var foregroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        AppSheetScaffold(
            title: entry.title,
            message: "\(entry.kind.displayName) • \(entry.feature)",
            headerAlignment: .leading,
            contentAlignment: .leading
        ) {
            VStack(alignment: .leading, spacing: 16) {
                infoSection(
                    title: "What happened",
                    body: entry.summary,
                    icon: "text.bubble"
                )

                infoSection(
                    title: "When this fires",
                    body: entry.whenItFires,
                    icon: "clock"
                )

                infoSection(
                    title: "Why we track it",
                    body: entry.whyTracked,
                    icon: "chart.line.uptrend.xyaxis"
                )

                infoSection(
                    title: "Destinations",
                    body: entry.destinationsSummary,
                    icon: "paperplane"
                )

                if !entry.parameters.isEmpty {
                    parameterSection
                }

                infoSection(
                    title: "Internal name",
                    body: entry.rawName,
                    icon: "curlybraces"
                )
            }
        } footer: {
            Button("Done") {
                dismiss()
            }
            .appSheetButtonStyle(tone: .primary)
        }
    }

    private var parameterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fields in this event")
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(foregroundColor)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(entry.parameters) { parameter in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(parameter.key)
                                .font(.montserratSemiBold(size: 13))
                                .foregroundStyle(foregroundColor)

                            Spacer()

                            Text(parameter.value)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Text(
                            parameter.helpText
                                ?? "This field adds extra context to help interpret the event."
                        )
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.secondary)
                    }

                    if parameter.id != entry.parameters.last?.id {
                        Divider()
                            .overlay(Color.secondary.opacity(0.18))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func infoSection(title: String, body: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.accent)

                Text(title)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(foregroundColor)
            }

            Text(body)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}
#endif
