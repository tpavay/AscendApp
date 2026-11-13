import SwiftUI

/// The 42 pt picture in the climber's row, which is also the button that opens the photo picker.
/// Initials on grey until there is a photo, with a small lime camera badge while there is none.
struct ProfilePhotoAvatar: View {
    let draft: ProfileSetupDraft
    let photoURL: URL?

    var body: some View {
        ClimberAvatar(
            userId: nil,
            isCurrentUser: true,
            photoURL: photoURL,
            placeholder: .initials(
                draft.initials,
                fill: Color(hex: "2A2A2A"),
                foreground: Color(hex: "CFCFCF"),
                fontSize: 15
            ),
            size: 42,
            showsChampionMark: false
        )
        .keyframeAnimator(initialValue: 1.0, trigger: photoURL) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            // A photo pops in: from 0.6 past full size and back, the way the design draws it.
            KeyframeTrack {
                LinearKeyframe(0.6, duration: 0.001)
                CubicKeyframe(1.08, duration: 0.25)
                CubicKeyframe(1.0, duration: 0.1)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if photoURL == nil {
                Image(systemName: "camera.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(OnboardingV3Palette.accent))
                    .overlay(Circle().strokeBorder(Color(hex: "111111"), lineWidth: 2))
                    .offset(x: 6, y: 6)
                    .accessibilityHidden(true)
            }
        }
    }
}
