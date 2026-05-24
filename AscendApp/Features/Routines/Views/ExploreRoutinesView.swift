import SwiftUI

struct ExploreRoutinesView: View {
    let routines: [Routine]
    var onRoutineSelected: ((Routine) -> Void)? = nil
    var onCopyRoutine: ((Routine) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var searchText = ""

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var filteredRoutines: [Routine] {
        if searchText.isEmpty {
            return routines
        }
        return routines.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredRoutines) { routine in
                        ExploreRoutineCard(
                            routine: routine,
                            onTap: { onRoutineSelected?(routine) },
                            onCopy: { onCopyRoutine?(routine) }
                        )
                    }
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("Explore Routines")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search templates")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(.accent)
                }
            }
        }
    }
}

// MARK: - Explore Routine Card

struct ExploreRoutineCard: View {
    let routine: Routine
    var onTap: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        RoutineCardSurface(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text(routine.name)
                        .font(.montserratSemiBold(size: 18))
                        .foregroundStyle(.white)

                    Spacer()

                    if let difficulty = routine.difficulty {
                        DifficultyIndicator(level: difficulty)
                    }
                }

                // Stats
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .medium))
                        Text(routine.totalDurationFormatted)
                            .font(.montserratMedium(size: 14))
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 12, weight: .medium))
                        Text("\(routine.intervalCount) intervals")
                            .font(.montserratMedium(size: 14))
                    }
                }
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: { onTap?() }) {
                        Text("View")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.accent, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: { onCopy?() }) {
                        Text("Copy")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.accent)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

#Preview {
    ExploreRoutinesView(
        routines: BuiltInRoutines.previewTemplates
    )
    .preferredColorScheme(.dark)
}
