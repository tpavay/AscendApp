import SwiftUI

struct ClimbBrowseHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var primaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.62)
    }

    private var quickStartSteps: [(title: String, description: String)] {
        [
            (
                title: "Connect headphones",
                description: "Live climb attempts require compatible headphones with motion tracking."
            ),
            (
                title: "Browse or search",
                description: "Spin the globe or use search to find a landmark climb you want to race."
            ),
            (
                title: "Start live",
                description: "Open a climb and start a live attempt when your headphones are connected."
            ),
            (
                title: "Earn the card",
                description: "Complete the live attempt to add the landmark card to your collection."
            )
        ]
    }

    private var progressRules: [String] {
        [
            "Only a live attempt completes a Live Climb - a routine never does.",
            "Catalog climbs must be finished in one live attempt.",
            "Ending early saves a DNF attempt in your history, not a leaderboard time.",
            "Completed Live Climbs stay visible so you can revisit the detail screen and history later."
        ]
    }

    var body: some View {
        AppSheetScaffold(
            title: "How Live Climbs Work",
            message: "Race real landmarks with headphone motion and earn climb cards.",
            headerAlignment: .leading,
            contentAlignment: .leading
        ) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionCard(
                        title: "Quick Start",
                        subtitle: "The basic loop from first browse to completion."
                    ) {
                        VStack(spacing: 12) {
                            ForEach(Array(quickStartSteps.enumerated()), id: \.offset) { index, step in
                                quickStartRow(
                                    number: index + 1,
                                    title: step.title,
                                    description: step.description
                                )
                            }
                        }
                    }

                    sectionCard(
                        title: "Map Icons",
                        subtitle: "These pin states tell you what each climb is doing right now."
                    ) {
                        VStack(spacing: 12) {
                            legendRow(
                                title: "Available",
                                description: "A climb you can preview and start.",
                                climb: .preview,
                                isCompleted: false,
                                isHighlighted: false
                            )

                            legendRow(
                                title: "Coming Soon",
                                description: "A future climb pinned on the globe but not open yet.",
                                climb: .previewComingSoon,
                                isCompleted: false,
                                isHighlighted: false
                            )

                            legendRow(
                                title: "Completed",
                                description: "A climb you have already finished at least once.",
                                climb: .preview,
                                isCompleted: true,
                                isHighlighted: false
                            )
                        }
                    }

                    sectionCard(
                        title: "Tiers",
                        subtitle: "Higher tiers mean longer landmarks and bigger step targets."
                    ) {
                        VStack(spacing: 10) {
                            ForEach(ClimbTier.allCases, id: \.self) { tier in
                                tierRow(tier)
                            }
                        }
                    }

                    sectionCard(
                        title: "Progress Rules",
                        subtitle: "A few details that matter once you start."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(progressRules, id: \.self) { rule in
                                progressRuleRow(rule)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            Button("Got it") {
                dismiss()
            }
            .appSheetButtonStyle(tone: .primary)
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(primaryTextColor)

                Text(subtitle)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(16)
        .appSheetCardStyle()
    }

    private func quickStartRow(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.montserratBold(size: 14))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.accent))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(primaryTextColor)

                Text(description)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendRow(
        title: String,
        description: String,
        climb: Climb,
        isCompleted: Bool,
        isHighlighted: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ClimbPinView(
                climb: climb,
                isCompleted: isCompleted,
                isHighlighted: isHighlighted
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(primaryTextColor)

                Text(description)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tierRow(_ tier: ClimbTier) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tier.color)
                .frame(width: 12, height: 12)

            Text(tier.displayName)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(primaryTextColor)

            Spacer(minLength: 12)

            Text(tier.stepRangeDescription)
                .font(.montserratMedium(size: 12))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressRuleRow(_ rule: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.accent)
                .padding(.top, 1)

            Text(rule)
                .font(.montserratRegular(size: 13))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ClimbBrowseHelpSheet()
        .appSheetStyle(.fraction(0.8))
}
