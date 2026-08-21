import SwiftUI

/// Full-screen background picker: a real Camera Roll grid (photo/video) and
/// Presets. Photos permission is requested at first use by the grid itself.
struct ShareBackgroundPickerView: View {
    let title: String
    let presets: [ShareComposerPreset]
    /// Which tabs to draw. The same value the sources coach mark describes, so the pill and the
    /// card can never name a different set of sources.
    let sourceOptions: ShareComposerSourceOptions
    /// Optional one-tap recap cards (climb hero + auto-arranged stats).
    var recap: RecapPreview?
    let onPick: (ShareBackgroundSource) -> Void
    var onPickRecap: ((ShareCardTemplate) -> Void)?
    let onClose: () -> Void
    let walkthrough: ShareComposerWalkthroughCoordinator

    @State private var selectedTab: Tab = .cameraRoll
    @AccessibilityFocusState private var sourceTabsAreFocused: Bool

    private let accent = Color(red: 0.706, green: 0.8, blue: 0)

    enum Tab { case cameraRoll, presets, recaps }

    /// The templates offered on the Recaps tab, with the data they render against.
    struct RecapPreview {
        let templates: [ShareCardTemplate]
        let context: ShareCardRenderContext
        let climb: Climb?
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabPill
                    .accessibilityFocused($sourceTabsAreFocused)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                switch visibleTab {
                case .cameraRoll:
                    ShareCameraRollGrid(onPick: onPick)
                case .presets:
                    presetsContent
                case .recaps:
                    recapsContent
                }

                Spacer(minLength: 0)
            }
        }
        .onChange(of: walkthrough.restingFocusTarget) { _, target in
            guard target == .sources else { return }
            sourceTabsAreFocused = true
        }
    }

    /// A selection can only ever name a tab the pill is drawing.
    private var visibleTab: Tab {
        switch selectedTab {
        case .presets:
            return offersPresets ? .presets : .cameraRoll
        case .recaps:
            return offersRecaps ? .recaps : .cameraRoll
        case .cameraRoll:
            return .cameraRoll
        }
    }

    private var offersPresets: Bool {
        sourceOptions.hasPresets && !presets.isEmpty
    }

    /// A tab is only offered once it has something behind it: recap templates resolve after the
    /// first render, and a failed load leaves none at all.
    private var offersRecaps: Bool {
        guard sourceOptions.hasRecaps, let recap, !recap.templates.isEmpty else { return false }
        return onPickRecap != nil
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 44, height: 44)
                }
                Spacer()
            }
            .overlay {
                Text("Select background")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(.white)
            }

            Text("to share \(title)")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(Color.customGray)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Tabs

    private var tabPill: some View {
        HStack(spacing: 0) {
            tabButton("Camera Roll", tab: .cameraRoll)
            if offersPresets {
                tabButton("Presets", tab: .presets)
            }
            if offersRecaps {
                tabButton("Recaps", tab: .recaps)
            }
        }
        .padding(4)
        .background(.white.opacity(0.06), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .shareComposerCoachMarkTarget(.sources)
        .padding(.horizontal, 24)
    }

    private func tabButton(_ label: String, tab: Tab) -> some View {
        Button {
            guard selectedTab != tab else { return }
            HapticsManager.shared.trigger(.lightImpact)
            selectedTab = tab
        } label: {
            Text(label)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(visibleTab == tab ? .white : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background {
                    if visibleTab == tab {
                        Capsule(style: .continuous).fill(.white.opacity(0.12))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Presets

    // MARK: - Presets (backgrounds we offer)

    private var presetsContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(presets) { preset in
                    Button {
                        HapticsManager.shared.trigger(.lightImpact)
                        onPick(.preset(preset))
                    } label: {
                        ShareBackgroundView(source: .preset(preset), isStatic: true)
                            .frame(maxWidth: .infinity)
                            .frame(height: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.accessibilityLabel)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }

    // MARK: - Recaps (our pre-made climb cards)

    private var recapsContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                if offersRecaps, let recap, let onPickRecap {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)
                        ],
                        spacing: 16
                    ) {
                        ForEach(recap.templates) { template in
                            Button {
                                HapticsManager.shared.trigger(.lightImpact)
                                onPickRecap(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ShareRecapThumbnail(
                                        template: template,
                                        context: recap.context,
                                        climb: recap.climb
                                    )
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(accent.opacity(0.34), lineWidth: 1)
                                        )

                                    Text(template.title)
                                        .font(.montserratSemiBold(size: 12))
                                        .foregroundStyle(.white.opacity(0.86))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Pick a layout, then add stickers on top or save it as-is.")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(Color.customGray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }
}

private struct ShareRecapThumbnail: View {
    let template: ShareCardTemplate
    let context: ShareCardRenderContext
    let climb: Climb?

    var body: some View {
        Color.black
            .aspectRatio(ShareCardTemplateView.aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    ShareCardTemplateView(
                        template: template,
                        context: context,
                        artwork: ShareCardArtworkSource(climb: climb)
                    )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity)
    }
}
