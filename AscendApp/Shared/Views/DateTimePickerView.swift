//
//  DateTimePickerView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/19/25.
//

import SwiftUI

struct DateTimePickerView: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var tempDate: Date
    
    init(selectedDate: Binding<Date>) {
        self._selectedDate = selectedDate
        self._tempDate = State(initialValue: selectedDate.wrappedValue)
    }
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        AppSheetScaffold(title: "Select Date & Time", layout: .picker) {
            DatePicker("", selection: $tempDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .accentColor(.accent)
                .labelsHidden()
        } footer: {
            HStack(spacing: 12) {
                Button(action: {
                    dismiss()
                }) {
                    Text("Cancel")
                }
                .appSheetButtonStyle(tone: .secondary)
                
                Button(action: {
                    selectedDate = tempDate
                    dismiss()
                }) {
                    Text("Done")
                }
                .appSheetButtonStyle(tone: .primary)
            }
        }
    }
}
