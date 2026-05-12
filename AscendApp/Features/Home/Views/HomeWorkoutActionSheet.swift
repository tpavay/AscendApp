import SwiftUI

struct HomeWorkoutActionSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    let onManualEntry: () -> Void
    let onJustClimb: () -> Void
    let onStartRoutine: () -> Void
    let onImportWorkouts: () -> Void
    let pendingImportCount: Int

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var primaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.58)
    }

    private var cardFill: Color {
        effectiveColorScheme == .dark ? Color.jetLighter.opacity(0.34) : .black.opacity(0.04)
    }

    private var cardStroke: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    private var secondaryIconColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.74) : .black.opacity(0.68)
    }

    private var secondaryIconFill: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06)
    }

    private var secondaryIconStroke: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    private var sheetTitle: String {
        "Add Workout"
    }

    private var sheetSubtitle: String {
        "Choose live tracking, manual entry, routine, or import."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            workoutActions
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .appSheetBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sheetTitle)
                .font(.montserratBold(size: 24))
                .foregroundStyle(primaryTextColor)

            Text(sheetSubtitle)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workoutActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("METHOD")
                .font(.montserratSemiBold(size: 11))
                .tracking(1.0)
                .foregroundStyle(secondaryTextColor)

            primaryActionButton(action: onJustClimb)

            HStack(spacing: 10) {
                secondaryActionTile(
                    action: onManualEntry,
                    systemImage: "square.and.pencil",
                    title: "Manual",
                    subtitle: "Steps and time"
                )

                secondaryActionTile(
                    action: onStartRoutine,
                    systemImage: "timer",
                    title: "Start Routine",
                    subtitle: "Guided intervals"
                )
            }

            secondaryActionTile(
                action: onImportWorkouts,
                systemImage: "tray.and.arrow.down",
                title: pendingImportCount > 0 ? "Review Imports" : "Import Workouts",
                subtitle: "Apple Health",
                badgeCount: pendingImportCount
            )
        }
    }

    private func primaryActionButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.black.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(.black.opacity(0.12), lineWidth: 1)
                            )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Just Climb")
                        .font(.montserratBold(size: 17))
                        .foregroundStyle(.black)

                    Text("Track live and end anytime")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.black.opacity(0.62))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black.opacity(0.72))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.accent)
            )
        }
        .buttonStyle(.plain)
    }

    private func secondaryActionTile(
        action: @escaping () -> Void,
        systemImage: String,
        title: String,
        subtitle: String,
        badgeCount: Int = 0
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(secondaryIconColor)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(secondaryIconFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(secondaryIconStroke, lineWidth: 1)
                                    )
                            )

                        if badgeCount > 0 {
                            Text("\(badgeCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 15, minHeight: 15)
                                .background(Circle().fill(.red))
                                .offset(x: 4, y: -4)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(secondaryTextColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(cardStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
