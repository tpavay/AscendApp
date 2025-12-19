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
        VStack(spacing: 12) {
            Text("Duration")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 16)

            Divider()
                .padding(.horizontal)

            HStack(alignment: .center, spacing: 0) {
                pickerColumn(title: "Hours", range: hourRange, selection: $hours, unit: "hr")
                pickerColumn(title: "Minutes", range: minuteSecondRange, selection: $minutes, unit: "min")
                pickerColumn(title: "Seconds", range: minuteSecondRange, selection: $seconds, unit: "sec")
            }
            .padding(.horizontal, 8)

            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.accent)
                    )
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
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
