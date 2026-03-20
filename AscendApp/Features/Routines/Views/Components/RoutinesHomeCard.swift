import SwiftUI
import SwiftData

struct RoutinesHomeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var routineService: RoutineService?
    @State private var routines: [Routine] = []
    @State private var isLoading = true
    @State private var selectedRoutine: Routine?
    @State private var activeRoutine: Routine?
    @State private var routineToEdit: Routine?

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with title and "See All" link
            HStack {
                Text("ROUTINES")
                    .font(.montserratSemiBold(size: 12))
                    .tracking(0.8)
                    .foregroundStyle(Color.customGray)

                Spacer()

                NavigationLink(destination: RoutinesView()) {
                    HStack(spacing: 4) {
                        Text("See All")
                            .font(.montserratSemiBold(size: 14))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.accent)
                }
                .buttonStyle(.plain)
            }

            // Content
            if isLoading {
                loadingState
            } else if routines.isEmpty {
                emptyState
            } else {
                routinePreviewScroll
            }
        }
        .onAppear {
            loadRoutines()
        }
        .onReceive(NotificationCenter.default.publisher(for: .routineTemplatesDidChange)) { _ in
            loadRoutines()
        }
        .sheet(item: $selectedRoutine) { routine in
            RoutineDetailView(
                routine: routine,
                onStart: {
                    selectedRoutine = nil
                    // Small delay to let sheet dismiss before presenting fullScreenCover
                    Task {
                        try await Task.sleep(for: .milliseconds(300))
                        activeRoutine = routine
                    }
                },
                onEdit: {
                    routineToEdit = routine
                    selectedRoutine = nil
                },
                onCopy: {
                    if let service = routineService {
                        do {
                            _ = try service.copyBuiltInRoutine(routine)
                            loadRoutines()
                            HapticsManager.shared.trigger(.success)
                        } catch {
                            print("Failed to copy routine: \(error)")
                        }
                    }
                },
                onDelete: {
                    if let service = routineService {
                        do {
                            try service.deleteRoutine(routine)
                            loadRoutines()
                            HapticsManager.shared.trigger(.mediumImpact)
                        } catch {
                            print("Failed to delete routine: \(error)")
                        }
                    }
                }
            )
            .appSheetStyle(.large)
        }
        .sheet(item: $routineToEdit) { routine in
            RoutineEditorView(
                routine: routine,
                onSave: { _ in
                    loadRoutines()
                }
            )
            .appSheetStyle(.large)
        }
        .fullScreenCover(item: $activeRoutine) { routine in
            ActiveRoutineView(routine: routine)
        }
    }

    private var loadingState: some View {
        HStack {
            ProgressView()
                .tint(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                .scaleEffect(0.8)
            Text("Loading...")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
        }
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        NavigationLink(destination: RoutinesView()) {
            HStack(spacing: 12) {
                AppIcon(token: .tabWorkouts, pointSize: 24)
                    .foregroundStyle(.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create guided workouts")
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Text("Build interval routines with intensity levels")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.5))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    private var routinePreviewScroll: some View {
        RoutineHorizontalRail(routines: Array(routines.prefix(6))) { routine in
            RoutineThumbnailCard(
                routine: routine,
                onTap: {
                    selectedRoutine = routine
                }
            )
        }
    }

    private func loadRoutines() {
        routineService = RoutineService(modelContext: modelContext)

        guard let service = routineService else {
            isLoading = false
            return
        }

        do {
            try service.ensureBuiltInRoutinesExist()
            routines = try service.getAllRoutines()
        } catch {
            print("Failed to load routines: \(error)")
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        VStack {
            RoutinesHomeCard()
                .padding(20)
            Spacer()
        }
    }
}

#Preview("Dark Mode") {
    NavigationStack {
        VStack {
            RoutinesHomeCard()
                .padding(20)
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
