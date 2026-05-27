import SwiftData
import SwiftUI

struct ProfileView: View {
    private let viewModel: ProfileScreenViewModel

    init(viewModel: ProfileScreenViewModel = ProfileScreenViewModel()) {
        self.viewModel = viewModel
    }

    var body: some View {
        OwnProfileView(viewModel: viewModel)
    }
}

#Preview("Profile") {
    NavigationStack {
        ProfileView()
    }
    .environment(AuthenticationViewModel())
    .environment(NetworkConnectivityService.shared)
    .modelContainer(
        for: [
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            LeaderboardStats.self
        ],
        inMemory: true
    )
    .preferredColorScheme(.dark)
}
