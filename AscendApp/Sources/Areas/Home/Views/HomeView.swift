//
//  HomeView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI

struct HomeView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            // Header Section
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome")
                    .font(.montserratRegular(size: 18))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(authVM.displayName.isEmpty ? "User" : authVM.displayName)
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Main Content Area
            VStack(spacing: 20) {
                // Placeholder content for now
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.1))
                    .frame(height: 200)
                    .overlay(
                        VStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(.accent)
                            
                            Text("Your workout data will appear here")
                                .font(.montserratMedium)
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                                .multilineTextAlignment(.center)
                        }
                    )
            }
            
            Spacer()
        }
        .padding(20)
        .themedBackground()
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AuthenticationViewModel())
    }
}
