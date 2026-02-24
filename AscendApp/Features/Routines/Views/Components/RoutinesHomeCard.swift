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
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

                Spacer()

                NavigationLink(destination: RoutinesView()) {
                    HStack(spacing: 4) {
                        Text("See All")
                            .font(.montserratMedium(size: 14))
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
            .presentationDetents([.large])
        }
        .sheet(item: $routineToEdit) { routine in
            RoutineEditorView(
                routine: routine,
                onSave: { _ in
                    loadRoutines()
                }
            )
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
                Image(systemName: "figure.stair.stepper")
                    .font(.system(size: 24, weight: .light))
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
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(routines.prefix(6)) { routine in
                    Button {
                        selectedRoutine = routine
                    } label: {
                        RoutinePreviewPill(routine: routine)
                    }
                    .buttonStyle(.plain)
                }

                if routines.count > 6 {
                    NavigationLink(destination: RoutinesView()) {
                        Text("+\(routines.count - 6) more")
                            .font(.montserratMedium(size: 12))
                            .foregroundStyle(.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.accent.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
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

// MARK: - Routine Preview Pill

struct RoutinePreviewPill: View {
    let routine: Routine

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(routine.name)
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(routine.totalDurationFormatted)
                    .font(.montserratRegular(size: 11))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

                if let difficulty = routine.difficulty {
                    DifficultyIndicator(level: difficulty)
                }
            }
        }
        .frame(minWidth: 140, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
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
