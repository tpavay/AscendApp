import SwiftUI

/// "Your athlete" under the climber's name on their own Profile: how they look on the Mountain,
/// and the way into the editor.
struct AthleteProfileCard: View {
    @Environment(AuthenticationViewModel.self) private var authVM

    @State private var store: AthleteLookStore
    @State private var unlocks: UnlockStore
    @State private var isEditing = false
    private let userId: (() -> String?)?

    init(store: AthleteLookStore = .shared, unlocks: UnlockStore = .shared, userId: (() -> String?)? = nil) {
        _store = State(initialValue: store)
        _unlocks = State(initialValue: unlocks)
        self.userId = userId
    }

    private var signedInUser: String? {
        userId?() ?? authVM.user?.uid
    }

    /// Earned items waiting to be looked at in the editor.
    private var newCount: Int {
        unlocks.isEnabled ? unlocks.newItems.count : 0
    }

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
            .overlay(alignment: .topTrailing) {
                if newCount > 0 {
                    Text("\(newCount) NEW")
                        .font(.montserratBold(size: 9.5))
                        .tracking(0.8)
                        .monospacedDigit()
                        .foregroundStyle(UnlockStyle.limeInk)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule(style: .continuous).fill(Color.accent))
                        .padding(12)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your athlete")
        .accessibilityValue(newCount > 0 ? "\(AthleteLookDescription.sentence(for: store.current)) \(newCount) new to wear." : AthleteLookDescription.sentence(for: store.current))
        .accessibilityHint("Opens the athlete editor.")
        .task(id: signedInUser) {
            guard let userId = signedInUser else { return }
            unlocks.load(userId: userId)
            await store.load(userId: userId)
        }
        .sheet(isPresented: $isEditing) {
            AthleteEditorView(store: store, unlocks: unlocks, userId: userId)
                .appSheetStyle(.large)
        }
    }
}
