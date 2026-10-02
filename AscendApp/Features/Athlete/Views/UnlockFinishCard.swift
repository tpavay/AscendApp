import FirebaseAuth
import SwiftData
import SwiftUI

/// The unlock moment on a finished climb's summary: the item this climb earned, with a button to
/// carry it, or - when it earned nothing - how far the climber is from the next one. Draws
/// nothing for a climb outside every event.
struct UnlockFinishCard: View {
    let workout: Workout

    @Environment(\.modelContext) private var modelContext
    @State private var unlocks = UnlockStore.shared
    @State private var outcome: UnlockClimbOutcome?
    @State private var carrying: AthleteGear?
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var appeared = false

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
            guard let userId = Auth.auth().currentUser?.uid else { return }
            await unlocks.refreshCatalogIfNeeded()
            outcome = unlocks.outcome(of: workout, userId: userId, modelContext: modelContext)
            carrying = AthleteLookStore.shared.current.carry
            withAnimation(.spring(duration: 0.5, bounce: 0.35).delay(0.25)) {
                appeared = true
            }
        }
    }

    private func unlocked(_ item: AthleteGear, outcome: UnlockClimbOutcome) -> some View {
        VStack(spacing: 12) {
            Text("\(outcome.progress.event.title.uppercased()) UNLOCK")
                .font(.montserratBold(size: 11))
                .tracking(1.4)
                .foregroundStyle(Color.accent)
            Image(item.thumbnailName)
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .scaleEffect(appeared ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)
            Text(item.title.uppercased())
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)
            Text(carrying == item ? "Your athlete carries it up the mountain." : "Earned. Carry it up the mountain.")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if outcome.newlyEarned.count > 1 {
                Text("Also earned: \(outcome.newlyEarned.dropLast().map(\.title).joined(separator: ", "))")
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            if carrying != item {
                Button {
                    carry(item)
                } label: {
                    Text(isSaving ? "SAVING..." : "CARRY IT")
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
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        saveFailed = false
        Task {
            defer { isSaving = false }
            do {
                try await AthleteLookStore.shared.carry(item, userId: userId)
                carrying = item
            } catch {
                saveFailed = true
                TelemetryManager.shared.recordError(error, context: .firestore, code: "athlete_look_save_failed")
            }
        }
    }
}
