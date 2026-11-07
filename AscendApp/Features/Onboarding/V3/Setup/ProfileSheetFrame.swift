import SwiftUI

/// The frame the birthday, height and weight sheets share: the title at the top left, an optional
/// unit toggle beside it, Done at the top right, and a one-line note at the bottom.
///
/// The sheet's own surface is the system's; this draws the design's #151515 over all of it, so the
/// rounded top corners come from the sheet and the colour from here.
struct ProfileSheetFrame<Content: View>: View {
    let title: String
    var units: ProfileSheetUnits?
    let note: String
    let onDone: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.custom("Montserrat-Black", size: 18, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                if let units {
                    ProfileUnitToggle(units: units)
                }

                Spacer(minLength: 0)

                Button("Done", action: onDone)
                    .font(.custom("Montserrat-ExtraBold", size: 16, relativeTo: .body))
                    .foregroundStyle(OnboardingV3Palette.accent)
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
            }

            content

            Text(note)
                .font(.custom("Montserrat-SemiBold", size: 12, relativeTo: .caption))
                .foregroundStyle(OnboardingV3Palette.footnote)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OnboardingV3Palette.sheetFill.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }
}

/// The two-option unit switch beside a sheet's title: `ft . in | cm`, `lb | kg`.
private struct ProfileUnitToggle: View {
    let units: ProfileSheetUnits

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(units.options.enumerated()), id: \.offset) { index, label in
                let isSelected = index == units.selected

                Button {
                    guard !isSelected else { return }
                    HapticsManager.shared.trigger(.selection)
                    units.onSelect(index)
                } label: {
                    Text(label)
                        .font(.custom("Montserrat-ExtraBold", size: 11.5, relativeTo: .caption))
                        .foregroundStyle(isSelected ? Color.white : Color(hex: "7A7A7A"))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? Color(hex: "2A2A2A") : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(OnboardingV3Palette.cardFill)
        )
    }
}
