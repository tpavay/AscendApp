import SwiftUI

/// Average heart rate for a climb logged by hand: one big number typed on the same keypad as
/// steps and time, so the sheet never raises the system keyboard over the form behind it.
/// Normalises into the same 25-230 range every other heart-rate entry point accepts, and an
/// emptied field saved clears the value.
struct LogClimbHeartRateSheet: View {
    @Binding var heartRate: Int?
    @Environment(\.dismiss) private var dismiss
    @State private var digits: String

    init(heartRate: Binding<Int?>) {
        _heartRate = heartRate
        _digits = State(initialValue: heartRate.wrappedValue.map(String.init) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Average heart rate")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(.white)

                Spacer()

                Button("Done") {
                    heartRate = Int(WorkoutInputValidation.normalizeHeartRateOnSubmit(digits))
                    dismiss()
                }
                .font(.montserratBold(size: 16))
                .foregroundStyle(Color.accent)
                .accessibilityLabel("Done")
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(digits.isEmpty ? "0" : digits)
                    .font(.montserratBold(size: 44))
                    .foregroundStyle(digits.isEmpty ? .white.opacity(0.28) : .white)
                    .monospacedDigit()

                Rectangle()
                    .fill(Color.accent)
                    .frame(width: 3, height: 38)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
                    .accessibilityHidden(true)

                Text("bpm")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 4)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.accent, lineWidth: 2)
                    )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Average heart rate")
            .accessibilityValue(digits.isEmpty ? "empty" : "\(digits) beats per minute")

            Text("From your watch or the machine's grips.")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.55))

            LogClimbKeypad(
                onDigit: { digit in
                    guard digits.count < 3 else { return }
                    // A leading zero would only ever be dropped on Done, so it never shows.
                    guard !(digits.isEmpty && digit == 0) else { return }
                    digits.append(String(digit))
                },
                onDelete: {
                    guard !digits.isEmpty else { return }
                    digits.removeLast()
                }
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .background(Color.black)
    }
}

/// A note on a climb logged by hand.
struct LogClimbNoteSheet: View {
    @Binding var note: String
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(note: Binding<String>) {
        _note = note
        _text = State(initialValue: note.wrappedValue)
    }

    var body: some View {
        AppSheetScaffold(title: "Add a note", layout: .picker) {
            TextEditor(text: $text)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .font(.montserratRegular(size: 16))
                .foregroundStyle(.white)
                .padding(12)
                .frame(minHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .onChange(of: text) { _, newValue in
                    if newValue.count > WorkoutInputValidation.notesMaxLength {
                        text = String(newValue.prefix(WorkoutInputValidation.notesMaxLength))
                    }
                }
                .onAppear { isFocused = true }
        } footer: {
            HStack(spacing: 12) {
                Button {
                    note = ""
                    dismiss()
                } label: {
                    Text("Clear")
                }
                .appSheetButtonStyle(tone: .secondary)

                Button {
                    note = text
                    dismiss()
                } label: {
                    Text("Done")
                }
                .appSheetButtonStyle(tone: .primary)
            }
        }
    }
}

/// Photos on an imported climb, from its quick edit; Log a climb picks in place on its own form.
/// They upload when the edit is saved, not when they are picked, so backing out of the sheet
/// leaves nothing in Storage.
struct LogClimbPhotoSheet: View {
    @Binding var selectedPhotos: [SelectedPhotoItem]
    @Binding var highlightedPhotoId: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppSheetScaffold(title: "Add photos", layout: .picker) {
            PhotoGalleryView(
                selectedImages: $selectedPhotos,
                highlightedSelectedItemId: $highlightedPhotoId
            )
        } footer: {
            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .appSheetButtonStyle(tone: .primary)
        }
    }
}
