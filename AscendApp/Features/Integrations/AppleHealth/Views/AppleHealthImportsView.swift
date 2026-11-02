import SwiftData
import SwiftUI

/// IMPORTS: the stair workouts Apple Health holds, waiting or already climbs.
///
/// Importing never opens a sheet or a dialog - a tap moves the row and a toast offers Undo. An
/// imported row opens the same full climb summary as any other climb; editing and removing live
/// there.
struct AppleHealthImportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<HealthWorkoutRecord> {
            $0.stateRawValue == "not_imported" || $0.stateRawValue == "imported"
        },
        sort: \HealthWorkoutRecord.startDate,
        order: .reverse
    )
    private var records: [HealthWorkoutRecord]

    @Query(
        filter: #Predicate<Workout> { $0.sourceRawValue == "apple_health" },
        sort: \Workout.date,
        order: .reverse
    )
    private var importedClimbs: [Workout]

    @State private var viewModel: AppleHealthImportsViewModel
    @State private var openClimb: Workout?

    init(viewModel: AppleHealthImportsViewModel = AppleHealthImportsViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        let sections = ImportsSections.make(
            records: records,
            climbs: Dictionary(
                importedClimbs.map { ($0.id, (steps: $0.steps, duration: $0.duration)) },
                uniquingKeysWith: { first, _ in first }
            ),
            now: Date()
        )

        VStack(spacing: 0) {
            header

            List {
                autoImportCard

                if !sections.notImported.isEmpty {
                    Section {
                        ForEach(sections.notImported) { row in
                            waitingRow(row)
                        }
                    } header: {
                        sectionTitle("NOT IMPORTED")
                    }
                }

                if !sections.thisWeek.isEmpty {
                    importedSection("This week", rows: sections.thisWeek, leadsImported: true)
                }
                if !sections.earlier.isEmpty {
                    importedSection("Earlier", rows: sections.earlier, leadsImported: sections.thisWeek.isEmpty)
                }

                if sections.isEmpty {
                    emptyState
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 120, for: .scrollContent)
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            bottomBar(waiting: sections.notImported)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(item: $openClimb) { climb in
            WorkoutDetailView(workout: climb, embedsInNavigationStack: false)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: sections)
        .animation(.easeInOut(duration: 0.2), value: viewModel.toast)
        .task { await viewModel.onAppear() }
        .trackOnce(screen: .appleHealthImports)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("IMPORTS")
                .font(.montserratBold(size: 16))
                .tracking(1.6)
                .foregroundStyle(.white)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .accessibilityLabel("Back")

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Auto-import

    private var autoImportCard: some View {
        HStack(spacing: 14) {
            healthIcon

            VStack(alignment: .leading, spacing: 3) {
                Text("Auto-import")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.white)
                Text(viewModel.autoImportSubtitle)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Toggle(
                "Auto-import",
                isOn: Binding(
                    get: { viewModel.isAutoImportEnabled },
                    set: { isOn in Task { await viewModel.setAutoImportEnabled(isOn) } }
                )
            )
            .labelsHidden()
            .tint(Color.accent)
        }
        .padding(.vertical, 6)
        .listRowBackground(rowBackground)
    }

    // MARK: - Rows

    /// `leadsImported` puts the IMPORTED label above the first imported group's own label.
    private func importedSection(_ title: String, rows: [ImportsRow], leadsImported: Bool) -> some View {
        Section {
            ForEach(rows) { row in
                importedRow(row)
            }
        } header: {
            VStack(alignment: .leading, spacing: 14) {
                if leadsImported {
                    sectionTitle("IMPORTED")
                }
                Text(title)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(nil)
            }
        }
    }

    private func waitingRow(_ row: ImportsRow) -> some View {
        HStack(spacing: 14) {
            healthIcon
            rowText(row)
            Spacer(minLength: 8)

            Button {
                Task { await viewModel.importOne(row.id) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Import \(ImportsRowFormat.stepsText(row.steps)) workout")
        }
        .padding(.vertical, 4)
        .listRowBackground(rowBackground)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                viewModel.skip(row.id)
            } label: {
                Text("Skip")
            }
            .tint(.gray)
        }
    }

    private func importedRow(_ row: ImportsRow) -> some View {
        Button {
            guard let climbID = row.climbID else { return }
            openClimb = importedClimbs.first { $0.id == climbID }
        } label: {
            HStack(spacing: 14) {
                healthIcon
                rowText(row)
                Spacer(minLength: 8)

                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.accent))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(rowBackground)
        .accessibilityHint("Opens the climb")
    }

    private func rowText(_ row: ImportsRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(ImportsRowFormat.stepsText(row.steps))
                    .font(.montserratBold(size: 17))
                    .foregroundStyle(.white)
                Text("·")
                    .foregroundStyle(.white.opacity(0.5))
                Text(ImportsRowFormat.durationText(row.duration))
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Text(ImportsRowFormat.whenText(row.startDate, now: Date()))
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.58))
        }
        .accessibilityElement(children: .combine)
    }

    private var healthIcon: some View {
        Image("appleHealth-icon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 36, height: 36)
            .clipShape(.rect(cornerRadius: 9))
            .accessibilityHidden(true)
    }

    private var rowBackground: some View {
        Color.white.opacity(0.07)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.montserratBold(size: 12))
            .tracking(1.8)
            .foregroundStyle(.white.opacity(0.5))
            .textCase(nil)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No stair stepper workouts yet")
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)
            Text("Finish one on any device that saves to Apple Health. It shows up here.")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .listRowBackground(Color.clear)
    }

    // MARK: - Bottom

    @ViewBuilder
    private func bottomBar(waiting: [ImportsRow]) -> some View {
        VStack(spacing: 10) {
            if let toast = viewModel.toast {
                importedToast(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !waiting.isEmpty {
                Button {
                    Task { await viewModel.importAll(waiting.map(\.id)) }
                } label: {
                    Text("IMPORT ALL (\(waiting.count))")
                        .tracking(2)
                }
                .buttonStyle(OnboardingPrimaryCTAButtonStyle(height: 58, cornerRadius: 14, fontSize: 17, tint: .accent))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func importedToast(_ toast: AppleHealthImportsViewModel.Toast) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accent))
                .accessibilityHidden(true)

            Text(toast.message)
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.updatesFrequently)

            Spacer(minLength: 8)

            Button {
                Task { await viewModel.undo() }
            } label: {
                Text("Undo")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(Color.accent)
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: toast.message)
        }
    }
}
