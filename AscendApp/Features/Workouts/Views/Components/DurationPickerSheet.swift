//
//  DurationPickerSheet.swift
//  AscendApp
//
//  Created by OpenAI Assistant on 2024-05-21.
//

import SwiftUI

struct DurationPickerSheet: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    var onDone: () -> Void

    // Support up to 99 hours (over 4 days) for long challenges
    private let hourRange = Array(0...99)
    private let minuteSecondRange = Array(0...59)

    var body: some View {
        AppSheetScaffold(title: "Duration", layout: .picker) {
            HStack(alignment: .center, spacing: 0) {
                pickerColumn(title: "Hours", range: hourRange, selection: $hours, unit: "hr")
                pickerColumn(title: "Minutes", range: minuteSecondRange, selection: $minutes, unit: "min")
                pickerColumn(title: "Seconds", range: minuteSecondRange, selection: $seconds, unit: "sec")
            }
            .padding(.horizontal, 8)
        } footer: {
            Button {
                onDone()
            } label: {
                HStack {
                    Spacer()
                    Text("Done")
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .appSheetButtonStyle(tone: .primary)
        }
    }

    private func pickerColumn(title: String, range: [Int], selection: Binding<Int>, unit: String) -> some View {
        Picker(title, selection: selection) {
            ForEach(range, id: \.self) { value in
                Text("\(value) \(unit)")
                    .font(.montserratMedium(size: 22))
                    .foregroundStyle(.white)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    @Previewable @State var hours = 1
    @Previewable @State var minutes = 30
    @Previewable @State var seconds = 15

    DurationPickerSheet(hours: $hours, minutes: $minutes, seconds: $seconds) {}
}
