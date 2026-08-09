//
//  WorkoutListEmptyStateView.swift
//  AscendApp
//
//  Created by Codex on 3/14/24.
//

import SwiftUI

struct WorkoutListEmptyStateView: View {
    let effectiveColorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            AppIcon(token: .tabWorkouts, pointSize: 60)
                .foregroundStyle(.accent)

            VStack(spacing: 8) {
                Text("No Climbs Yet")
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text("Race a landmark or just climb. Every session lands here.")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(20)
    }
}
