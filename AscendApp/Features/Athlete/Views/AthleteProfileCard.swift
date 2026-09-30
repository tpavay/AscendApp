import SwiftUI

/// "Your athlete" under the climber's name on their own Profile: how they look on the Mountain,
/// and the way into the editor.
struct AthleteProfileCard: View {
    @Environment(AuthenticationViewModel.self) private var authVM

    @State private var store = AthleteLookStore.shared
    @State private var isEditing = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            HStack(spacing: 16) {
                AthletePreviewView(look: store.current, turns: false, framing: .portrait)
                    .frame(width: 92, height: 108)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR ATHLETE")
                        .font(.montserratBold(size: 13))
                        .tracking(0.9)
                        .foregroundStyle(.white)
                    Text("How you race on the Mountain.")
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("EDIT")
                        .font(.montserratBold(size: 11))
                        .tracking(1)
                        .foregroundStyle(Color.accent)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ProfileVisualStyle.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ProfileVisualStyle.cardStroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your athlete")
        .accessibilityValue(AthleteLookDescription.sentence(for: store.current))
        .accessibilityHint("Opens the athlete editor.")
        .task(id: authVM.user?.uid) {
            guard let userId = authVM.user?.uid else { return }
            await store.load(userId: userId)
        }
        .sheet(isPresented: $isEditing) {
            AthleteEditorView(store: store)
                .appSheetStyle(.large)
        }
    }
}
