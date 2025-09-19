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
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 16)
            
            VStack(spacing: 20) {
                Text("Select Date & Time")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .padding(.top, 20)
                
                DatePicker("", selection: $tempDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
                    .accentColor(.accent)
                    .labelsHidden()
                
                HStack(spacing: 12) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.montserratSemiBold)
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                            )
                    }
                    
                    Button(action: {
                        selectedDate = tempDate
                        dismiss()
                    }) {
                        Text("Done")
                            .font(.montserratSemiBold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.accent)
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .themedBackground()
    }
}
