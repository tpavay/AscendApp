import FirebaseAuth
import SwiftData
import SwiftUI

/// The unlock moment on a saved climb's summary: the item this climb earned, with a button to
/// carry it, or - when it earned nothing - how far the climber is from the next one. Draws
/// nothing for a climb outside every event.
struct UnlockFinishCard: View {
    let workout: Workout

    @Environment(\.modelContext) private var modelContext
    @State private var unlocks = UnlockStore.shared
    @State private var outcome: UnlockClimbOutcome?
    @State private var equipped: AthleteGear?
    @State private var isSaving = false
    @State private var saveFailed = false
    /// The signed-in climber, read when the card needs it.
    private let currentUserId: @MainActor () -> String?

    init(workout: Workout, unlocks: UnlockStore = .shared, userId: @escaping @MainActor () -> String? = { Auth.auth().currentUser?.uid }) {
        self.workout = workout
        _unlocks = State(initialValue: unlocks)
        self.currentUserId = userId
    }

    var body: some View {
        Group {
            if let outcome {
                if let item = outcome.newlyEarned.last {
                    unlocked(item, outcome: outcome)
                } else {
                    progress(outcome.progress)
                }
            }
        }
        .task(id: workout.id) {
            guard let userId = currentUserId() else { return }
            await unlocks.refreshCatalogIfNeeded()
            outcome = unlocks.outcome(of: workout, userId: userId, modelContext: modelContext)
            equipped = AthleteLookStore.shared.current.gear.first { $0 == outcome?.newlyEarned.last }
        }
    }

    private func unlocked(_ item: AthleteGear, outcome: UnlockClimbOutcome) -> some View {
        VStack(spacing: 12) {
            Text("\(outcome.progress.event.title.uppercased()) UNLOCK")
                .font(.montserratBold(size: 11))
                .tracking(1.4)
                .foregroundStyle(Color.accent)
            UnlockRevealView(look: AthleteLookStore.shared.current, item: item)
                .frame(height: 260)
                .frame(maxWidth: .infinity)
            Text(item.title.uppercased())
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)
            Text(equipped == item ? "On your athlete. It goes up the mountain with you." : "Earned. Equip it on your athlete.")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if outcome.newlyEarned.count > 1 {
                Text("Also earned: \(outcome.newlyEarned.dropLast().map(\.title).joined(separator: ", "))")
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            if equipped != item {
                Button {
                    carry(item)
                } label: {
                    Text(isSaving ? "SAVING..." : "EQUIP ON YOUR ATHLETE")
                        .font(.montserratBold(size: 13))
                        .tracking(1.1)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accent))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            if saveFailed {
                Text("Couldn't save your athlete. Try again.")
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(cardBackground)
        .accessibilityElement(children: .contain)
    }

    private func progress(_ progress: UnlockEventProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.event.title.uppercased())
                    .font(.montserratBold(size: 11))
                    .tracking(1.4)
                    .foregroundStyle(Color.accent)
                Spacer(minLength: 8)
                Text(UnlockCopy.tally(progress))
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            let lines = UnlockCopy.nextLines(progress)
            if lines.isEmpty {
                Text("Every \(progress.event.title) item earned.")
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(.white)
            } else {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
    }

    private func carry(_ item: AthleteGear) {
        guard let userId = currentUserId() else { return }
        isSaving = true
        saveFailed = false
        Task {
            defer { isSaving = false }
            do {
                try await AthleteLookStore.shared.equip(item, userId: userId)
                unlocks.markSeen([item], userId: userId)
                equipped = item
            } catch {
                saveFailed = true
                TelemetryManager.shared.recordError(error, context: .firestore, code: "athlete_look_save_failed")
            }
        }
    }
}
