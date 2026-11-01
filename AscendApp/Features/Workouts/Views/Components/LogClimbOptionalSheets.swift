import SwiftUI

/// Average heart rate for a climb logged by hand. One number; the field normalises into the same
/// 25-230 range every other heart-rate entry point accepts.
struct LogClimbHeartRateSheet: View {
    @Binding var heartRate: Int?
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(heartRate: Binding<Int?>) {
        _heartRate = heartRate
        _text = State(initialValue: heartRate.wrappedValue.map(String.init) ?? "")
    }

    var body: some View {
        AppSheetScaffold(title: "Average heart rate", message: "Beats per minute.") {
            TextField("BPM", text: $text)
                .keyboardType(.numberPad)
                .focused($isFocused)
                .font(.montserratBold(size: 34))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .onChange(of: text) { _, newValue in
                    let digits = WorkoutInputValidation.filterNumericInput(newValue)
                    text = String(digits.prefix(3))
                }
                .onAppear { isFocused = true }
        } footer: {
            HStack(spacing: 12) {
                Button {
                    heartRate = nil
                    dismiss()
                } label: {
                    Text("Clear")
                }
                .appSheetButtonStyle(tone: .secondary)

                Button {
                    let normalized = WorkoutInputValidation.normalizeHeartRateOnSubmit(text)
                    heartRate = Int(normalized)
                    dismiss()
                } label: {
                    Text("Done")
                }
                .appSheetButtonStyle(tone: .primary)
            }
        }
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

/// Photos on a climb logged by hand. They upload when the climb is saved, not when they are
/// picked, so backing out of the screen leaves nothing in Storage.
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
