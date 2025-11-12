//
//  WorkoutListEmptyStateView.swift
//  AscendApp
//
//  Created by Codex on 3/14/24.
//

import SwiftUI

struct WorkoutListEmptyStateView: View {
    let effectiveColorScheme: ColorScheme
    let pendingImportCount: Int
    let onImportTapped: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "figure.stair.stepper")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.accent)
            
            VStack(spacing: 8) {
                Text("No Workouts Yet")
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Start tracking your stair climbing sessions")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onImportTapped) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .medium))
                    Text("Import Workouts")
                        .font(.montserratMedium(size: 16))
                    if pendingImportCount > 0 {
                        Text("(\(pendingImportCount))")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.accent)
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding(20)
    }
}
