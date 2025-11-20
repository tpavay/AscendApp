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

    private let hourRange = Array(0...23)
    private let minuteSecondRange = Array(0...59)

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(.secondary)
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            HStack {
                Text("Duration")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(.primary)

                Spacer()

                Button("Done") {
                    onDone()
                }
                .font(.montserratSemiBold(size: 16))
            }
            .padding(.horizontal)

            HStack(alignment: .center) {
                pickerColumn(title: "Hours", range: hourRange, selection: $hours, unit: "hr")
                pickerColumn(title: "Minutes", range: minuteSecondRange, selection: $minutes, unit: "min")
                pickerColumn(title: "Seconds", range: minuteSecondRange, selection: $seconds, unit: "sec")
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.bottom)
    }

    private func pickerColumn(title: String, range: [Int], selection: Binding<Int>, unit: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)

            Picker(title, selection: selection) {
                ForEach(range, id: \.self) { value in
                    Text("\(value) \(unit)")
                        .font(.montserratRegular(size: 16))
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    @Previewable @State var hours = 1
    @Previewable @State var minutes = 30
    @Previewable @State var seconds = 15

    DurationPickerSheet(hours: $hours, minutes: $minutes, seconds: $seconds) {}
}
