//
//  MainTabView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var tabRouter = TabRouter()
    @State private var hasCheckedRatingOnLaunch = false
    @State private var showingBaseLevelOnboarding = false

    // Easy configuration - just change this array to modify tabs
    private let tabs = TabItem.activeTabs

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        ZStack {
            ForEach(tabs) { tab in
                tab.view
                    .opacity(tabRouter.selectedTab == tab.identifier ? 1 : 0)
                    .allowsHitTesting(tabRouter.selectedTab == tab.identifier)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.25), value: tabRouter.selectedTab)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .accentColor(.accent)
        .environment(tabRouter)
        .onAppear {
            checkForRatingPromptOnLaunch()
            syncBaseLevelOnboardingPresentation()
        }
        .onChange(of: settingsManager.hasCompletedBaseLevelOnboarding) { _, _ in
            syncBaseLevelOnboardingPresentation()
        }
        .fullScreenCover(isPresented: $showingBaseLevelOnboarding) {
            BaseLevelOnboardingView()
        }
        .themeAware()
    }

    // MARK: - Custom Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabBarButton(for: tab)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background {
            tabBarBackground
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabBarButton(for tab: TabItem) -> some View {
        let isSelected = tabRouter.selectedTab == tab.identifier
        return Button {
            guard tabRouter.selectedTab != tab.identifier else { return }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            tabRouter.selectedTab = tab.identifier
        } label: {
            VStack(spacing: 3) {
                let iconToUse = iconToken(for: tab, isSelected: isSelected)
                tabBarIcon(for: iconToUse)
                    .frame(width: 24, height: 24)
                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.accent : effectiveColorScheme == .dark ? .white.opacity(0.6) : Color.gray)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabBarBackground: some View {
        if effectiveColorScheme == .dark {
            Rectangle()
                .fill(.ultraThinMaterial)
        } else {
            VStack(spacing: 0) {
                Divider()
                Rectangle()
                    .fill(Color(uiColor: .systemBackground))
            }
        }
    }

    // MARK: - Helpers

    private func checkForRatingPromptOnLaunch() {
        // Only check once per app session
        guard !hasCheckedRatingOnLaunch else { return }
        hasCheckedRatingOnLaunch = true

        // Check if user is eligible for rating prompt based on workout count
        // This handles cases where user imported workouts and became eligible
        // Note: We fetch count on-demand rather than using @Query to avoid crashes
        // when workouts are deleted (e.g., during account deletion) while this view is in the hierarchy
        let workoutCount = (try? modelContext.fetchCount(FetchDescriptor<Workout>())) ?? 0
        AppStoreRatingManager.shared.checkAndRequestReviewIfNeeded(currentWorkoutCount: workoutCount)
    }

    private func syncBaseLevelOnboardingPresentation() {
        let workoutCount = (try? modelContext.fetchCount(FetchDescriptor<Workout>())) ?? 0
        settingsManager.resolveBaseLevelBootstrap(hasWorkoutHistory: workoutCount > 0)
        showingBaseLevelOnboarding = settingsManager.shouldPresentBaseLevelOnboarding
    }

    private func iconToken(for tab: TabItem, isSelected: Bool) -> AppIconToken {
        if isSelected, let selectedIcon = tab.selectedIcon {
            return selectedIcon
        }
        return tab.icon
    }

    @ViewBuilder
    private func tabBarIcon(for token: AppIconToken) -> some View {
        switch token.source {
        case .asset(let name):
            Image(uiImage: resizedTabBarImage(named: name))
        case .systemSymbol:
            AppIcon(token: token, pointSize: 20)
        }
    }

    private func resizedTabBarImage(named name: String) -> UIImage {
        let size = CGSize(width: 24, height: 24)
        guard let sourceImage = UIImage(named: name) else {
            return UIImage(systemName: "questionmark.circle") ?? UIImage()
        }

        let format = UIGraphicsImageRendererFormat.default()
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let rendered = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: size))
        }

        return rendered.withRenderingMode(.alwaysTemplate)
    }
}

#Preview {
    MainTabView()
        .environment(AuthenticationViewModel())
}
