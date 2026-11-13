import SwiftUI

/// The detail menu's lead action. A share card states a climb's steps as a public claim, so a climb
/// with no step count offers Add steps until it has one.
struct WorkoutDetailShareOrAddStepsAction: View {
    let isMissingSteps: Bool
    let share: () -> Void
    let addSteps: () -> Void

    var body: some View {
        if isMissingSteps {
            Button(action: addSteps) {
                Label("Add steps", systemImage: "plus")
            }
        } else {
            Button(action: share) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}
