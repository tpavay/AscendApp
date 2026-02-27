//
//  ImportCelebrationView.swift
//  AscendApp
//

import SwiftUI

/// Full-screen celebration presented after a successful import
struct ImportCelebrationView: View {
    let data: ImportCelebrationData
    let onDismiss: () -> Void

    @State private var viewModel: ImportCelebrationViewModel?

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var backgroundGradient: LinearGradient {
        if effectiveColorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.black,
                    Color.jet.opacity(0.75),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.95, green: 0.98, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            // Background
            backgroundGradient
                .ignoresSafeArea()

            Circle()
                .fill(.accent.opacity(effectiveColorScheme == .dark ? 0.12 : 0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 72)
                .offset(y: -210)

            if let viewModel {
                StatsCelebrationScreen(viewModel: viewModel, onDone: onDismiss)
            }
        }
        .preferredColorScheme(effectiveColorScheme)
        .onAppear {
            let vm = ImportCelebrationViewModel(data: data)
            viewModel = vm
            TelemetryManager.shared.log(.celebrationShown)
            vm.startAnimations()
        }
        .onDisappear {
            viewModel?.cancelAnimations()
        }
    }
}
