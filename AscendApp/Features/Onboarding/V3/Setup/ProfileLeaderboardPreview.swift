import PhotosUI
import SwiftUI

/// Three leaderboard rows, the middle one the climber's own. It is what they will look like on every
/// board, so it follows the draft on every keystroke and every sheet's Done.
///
/// The rows above and below are dimmed stand-ins, not people: grey bars and a score, so nothing on
/// the screen can be mistaken for another climber.
struct ProfileLeaderboardPreview: View {
    let draft: ProfileSetupDraft
    /// Where the picked photo is on the device, if one is.
    let photoURL: URL?
    /// The photo the picker hands back; the avatar in the climber's row is the picker's button.
    @Binding var pickerItem: PhotosPickerItem?
    /// Fixes the clock for the age the birthday gives.
    var now: Date = .now
    /// Shorter rows for a phone shorter than the design's canvas.
    var isCompact = false

    var body: some View {
        VStack(spacing: isCompact ? 4 : 5) {
            PlaceholderRow(rank: "4", barWidth: 130, score: "2,410", height: isCompact ? 34 : 42)
            ownRow
            PlaceholderRow(rank: "6", barWidth: 100, score: "1,980", height: isCompact ? 34 : 42)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - The climber's row

    /// The photo prompt in lime until a photo is picked, then the grey details line.
    private var subline: ProfileSetupDraft.RowSubline? {
        draft.rowSubline(hasPhoto: photoURL != nil, on: now)
    }

    private var ownRow: some View {
        HStack(spacing: 12) {
            Text("5")
                .font(.custom("Montserrat-Black", fixedSize: 15))
                .foregroundStyle(OnboardingV3Palette.accent)
                .frame(width: 18)
                .accessibilityHidden(true)

            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                ProfilePhotoAvatar(draft: draft, photoURL: photoURL)
                    .frame(width: 54, height: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -6)
            .accessibilityLabel(photoURL == nil ? "Add a photo" : "Change photo")

            VStack(alignment: .leading, spacing: 3) {
                Text(draft.displayName)
                    .font(.custom("Montserrat-Black", size: 16, relativeTo: .body))
                    .foregroundStyle(draft.boardName == nil ? OnboardingV3Palette.skip : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let subline {
                    Text(subline.text)
                        .font(.custom("Montserrat-Bold", size: 12, relativeTo: .caption))
                        .foregroundStyle(subline == .photoPrompt ? OnboardingV3Palette.accent : Color(hex: "C8C8C8"))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Your leaderboard row, rank 5")
            .accessibilityValue([draft.displayName, subline?.text].compactMap { $0 }.joined(separator: ", "))

            Text("YOU")
                .font(.custom("Montserrat-Black", fixedSize: 12))
                .tracking(12 * 0.08)
                .foregroundStyle(OnboardingV3Palette.accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: isCompact ? 58 : 64)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "17220A"), OnboardingV3Palette.cardFill],
                        startPoint: UnitPoint(x: 0, y: 0.3),
                        endPoint: UnitPoint(x: 0.7, y: 0.7)
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OnboardingV3Palette.accent, lineWidth: 2)
        )
        .shadow(color: OnboardingV3Palette.accent.opacity(0.28), radius: 14)
    }
}

private struct PlaceholderRow: View {
    let rank: String
    let barWidth: CGFloat
    let score: String
    let height: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Text(rank)
                .font(.custom("Montserrat-ExtraBold", fixedSize: 13))
                .foregroundStyle(Color(hex: "8E8E8E"))
                .frame(width: 18)

            Circle()
                .fill(Color(hex: "262626"))
                .frame(width: 28, height: 28)

            Capsule()
                .fill(Color(hex: "262626"))
                .frame(width: barWidth, height: 8)

            Spacer(minLength: 0)

            Text(score)
                .font(.custom("Montserrat-ExtraBold", fixedSize: 13))
                .foregroundStyle(Color(hex: "8E8E8E"))
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "0A0A0A"))
        )
        .opacity(0.55)
        .accessibilityHidden(true)
    }
}
