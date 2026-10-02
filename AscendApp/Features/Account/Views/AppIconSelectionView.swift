import SwiftUI
import UIKit

/// Settings -> App Icon: the seasonal icon this build ships with, or the lime A.
struct AppIconSelectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var selection = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)
    @State private var failed = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(AppIconChoice.allCases) { choice in
                    row(choice)
                }
                if failed {
                    Text("Couldn't change the icon. Try again.")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .themedBackground()
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .trackOnce(screen: .appIconSettings)
    }

    private func row(_ choice: AppIconChoice) -> some View {
        let isSelected = selection == choice
        return Button {
            choose(choice)
        } label: {
            HStack(spacing: 16) {
                Image(choice.previewImageName)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.title)
                        .font(.montserratSemiBold)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    Text(choice.subtitle)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle()
                            .fill(.accent)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? .accent.opacity(0.5) : (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1)),
                                    lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.title) icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ choice: AppIconChoice) {
        guard choice != selection, UIApplication.shared.supportsAlternateIcons else { return }
        failed = false
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(choice.alternateIconName)
                selection = choice
            } catch {
                failed = true
            }
        }
    }
}
