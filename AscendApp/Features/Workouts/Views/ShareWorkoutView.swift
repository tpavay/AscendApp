//
//  ShareWorkoutView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/5/25.
//

import PhotosUI
import SwiftUI
import UIKit

struct ShareWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel: ShareWorkoutViewModel
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared

    @State private var showingBackgroundOptions = false
    @State private var sharePayload: ActivitySharePayload?
    @State private var shareErrorMessage: String?
    @State private var showingPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var copyConfirmationText: String?

    init(workout: Workout) {
        _viewModel = StateObject(wrappedValue: ShareWorkoutViewModel(workout: workout))
    }

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var actionForeground: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var actionBackground: Color {
        effectiveColorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                posterView

                Text("Share workout – Logged with Ascend")
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                actionRow

                Spacer()
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 20)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.accent)
                }
            }
        }
        .themedBackground()
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $photoPickerItem,
            matching: .images
        )
        .sheet(item: $sharePayload) { payload in
            ActivityView(activityItems: payload.items)
                .ignoresSafeArea()
        }
        .confirmationDialog("Background", isPresented: $showingBackgroundOptions, titleVisibility: .visible) {
            Button("Default") {
                viewModel.useDefaultBackground()
            }

            Button("Photo") {
                showingPhotoPicker = true
            }
        }
        .alert("Unable to Share", isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(shareErrorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let copyConfirmationText {
                Text(copyConfirmationText)
                    .font(.montserratSemiBold(size: 14))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.8))
                    )
                    .foregroundStyle(.white)
                    .padding(.top, 40)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .onChange(of: photoPickerItem) { _, newValue in
            guard let item = newValue else { return }
            Task {
                await loadImage(from: item)
            }
        }
    }

    private var posterView: some View {
        return WorkoutSharePoster(
            workout: viewModel.workout,
            usesPhotoBackground: viewModel.usesPhotoBackground,
            backgroundImage: viewModel.backgroundImage,
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight
        )
        .frame(
            width: ShareWorkoutViewModel.displayCardWidth,
            height: ShareWorkoutViewModel.displayCardHeight
        )
        .frame(maxWidth: .infinity)
        .overlay {
            if viewModel.isLoadingBackground {
                ZStack {
                    RoundedRectangle(cornerRadius: 32)
                        .fill(Color.black.opacity(0.35))
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 4)
    }

    private var actionRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ShareActionButton(
                    icon: "photo.on.rectangle",
                    title: "Change Background",
                    foregroundColor: actionForeground,
                    backgroundColor: actionBackground
                ) {
                    showingBackgroundOptions = true
                }

                ShareActionButton(
                    icon: "square.and.arrow.up",
                    title: "More",
                    foregroundColor: actionForeground,
                    backgroundColor: actionBackground
                ) {
                    sharePoster()
                }
            }

            ShareActionButton(
                icon: "doc.on.doc",
                title: "Copy Text",
                foregroundColor: actionForeground,
                backgroundColor: actionBackground
            ) {
                copyShareText()
            }
        }
    }

    private func sharePoster() {
        guard let image = viewModel.renderCurrentPoster(
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight
        ) else {
            shareErrorMessage = "We couldn't render the poster. Please try again."
            return
        }

        var items: [Any] = [image]
        let text = viewModel.shareText(
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight
        )
        items.append(ShareTextActivityItemSource(text: text))

        sharePayload = ActivitySharePayload(items: items)
    }

    private func copyShareText() {
        UIPasteboard.general.string = viewModel.shareText(
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight
        )
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            copyConfirmationText = "Copied!"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.3)) {
                copyConfirmationText = nil
            }
        }
    }

    private func loadImage(from pickerItem: PhotosPickerItem) async {
        await MainActor.run {
            viewModel.isLoadingBackground = true
        }

        do {
            if let data = try await pickerItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    viewModel.updateBackgroundImage(image)
                    photoPickerItem = nil
                    viewModel.isLoadingBackground = false
                }
                return
            }

            await MainActor.run {
                shareErrorMessage = "We couldn't load that photo. Please try another one."
                photoPickerItem = nil
                viewModel.isLoadingBackground = false
            }
        } catch {
            await MainActor.run {
                shareErrorMessage = "We couldn't load that photo. Please try another one."
                photoPickerItem = nil
                viewModel.isLoadingBackground = false
            }
        }
    }
}

private struct ShareActionButton: View {
    let icon: String
    let title: String
    let foregroundColor: Color
    let backgroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.montserratMedium(size: 13))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ActivitySharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}
