import SwiftUI

struct ProfileBirthdayEditorView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBirthday: Date
    @State private var isSaving = false

    init(birthday: ProfileBirthday?) {
        let defaultDate = Calendar.current.date(byAdding: .year, value: -32, to: .now) ?? .now
        _selectedBirthday = State(initialValue: birthday?.date() ?? defaultDate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProfileSection(title: "Personal Information") {
                    ProfileCardSurface {
                        DatePicker(
                            "Birthday",
                            selection: $selectedBirthday,
                            in: allowedRange,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("Birthday")
                        .accessibilityValue(selectedBirthday.formatted(date: .long, time: .omitted))
                    }
                }

                Button(action: save) {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Save")
                                .font(.montserratBold(size: 14))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(Color.accent))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .opacity(isSaving ? 0.7 : 1)

                if let errorMessage = authVM.errorMessage {
                    Text(errorMessage)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .themedBackground()
        .navigationTitle("Birthday")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .onAppear {
            authVM.errorMessage = nil
        }
    }

    private var allowedRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let oldest = calendar.date(byAdding: .year, value: -120, to: today) ?? today
        let youngest = calendar.date(byAdding: .year, value: -13, to: today) ?? today
        return oldest...youngest
    }

    private func save() {
        guard !isSaving else { return }

        Task { @MainActor in
            isSaving = true
            let didSave = await authVM.updateBirthday(
                ProfileBirthday(date: selectedBirthday)
            )
            isSaving = false
            if didSave {
                dismiss()
            }
        }
    }
}
