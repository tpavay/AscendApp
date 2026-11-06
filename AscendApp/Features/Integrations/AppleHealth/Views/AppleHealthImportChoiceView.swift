import SwiftUI

/// HOW SHOULD WE IMPORT THEM?: the one choice a climber connecting after onboarding makes.
/// Import automatically is preselected, and the choice is the same Auto-import setting Imports and
/// Settings show.
struct AppleHealthImportChoiceView: View {
    @Binding var choosesAutomatic: Bool
    let summary: String
    let isWorking: Bool
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(
            background: { Color.black },
            content: { layout in
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: HealthFlowChrome.contentTopClearance + 40)

                    Label("Apple Health connected", systemImage: "checkmark")
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.accent.opacity(0.1))
                                .overlay(Capsule().strokeBorder(Color.accent.opacity(0.25), lineWidth: 1))
                        )

                    VStack(alignment: .leading, spacing: 0) {
                        Text("HOW SHOULD WE")
                            .foregroundStyle(.white)
                        Text("IMPORT THEM?")
                            .foregroundStyle(Color.accent)
                    }
                    .font(.montserratBold(size: 34))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.top, 20)

                    Text(summary)
                        .font(.montserratRegular(size: 17))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)

                    VStack(spacing: 14) {
                        option(
                            isSelected: choosesAutomatic,
                            title: "Import automatically",
                            detail: "They show up in your climbs on their own. Edit or remove anytime."
                        ) { choosesAutomatic = true }

                        option(
                            isSelected: !choosesAutomatic,
                            title: "Let me choose",
                            detail: "Tap + on the ones you want to import."
                        ) { choosesAutomatic = false }
                    }
                    .padding(.top, 26)

                    Spacer(minLength: 140)
                }
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            bottomContent: { layout in
                HealthFlowBottomBar(
                    primaryTitle: "CONTINUE",
                    primaryHeight: layout.primaryButtonHeight,
                    caption: "You can change this anytime in Settings.",
                    isDisabled: isWorking,
                    onPrimary: onContinue
                )
            }
        )
        .preferredColorScheme(.dark)
        .trackOnce(screen: .appleHealthImportChoice)
    }

    private func option(
        isSelected: Bool,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accent : .white.opacity(0.22))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.montserratBold(size: 18))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.accent.opacity(0.07) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(isSelected ? Color.accent : .white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
