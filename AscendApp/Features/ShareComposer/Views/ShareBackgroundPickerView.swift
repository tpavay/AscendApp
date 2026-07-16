import SwiftUI

/// Full-screen background picker: a real Camera Roll grid (photo/video) and
/// Presets. Photos permission is requested at first use by the grid itself.
struct ShareBackgroundPickerView: View {
    let title: String
    let presets: [ShareComposerPreset]
    /// Optional one-tap recap card (climb hero + auto-arranged stats).
    var recap: RecapPreview?
    let onPick: (ShareBackgroundSource) -> Void
    var onPickRecap: ((ShareRecapTemplate) -> Void)?
    let onClose: () -> Void

    @State private var selectedTab: Tab = .cameraRoll

    private let accent = Color(red: 0.706, green: 0.8, blue: 0)

    enum Tab { case cameraRoll, presets, recaps }

    /// Data for the Recaps tab card (our pre-made climb card).
    struct RecapPreview {
        let data: ShareRecapCardData
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabPill
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                switch selectedTab {
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
            tabButton("Presets", tab: .presets)
            if recap != nil {
                tabButton("Recaps", tab: .recaps)
            }
        }
        .padding(4)
        .background(.white.opacity(0.06), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
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
                .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    if selectedTab == tab {
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
                if let recap, let onPickRecap {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)
                        ],
                        spacing: 16
                    ) {
                        ForEach(ShareRecapTemplate.allCases) { template in
                            Button {
                                HapticsManager.shared.trigger(.lightImpact)
                                onPickRecap(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ShareRecapThumbnail(template: template, data: recap.data)
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
    let template: ShareRecapTemplate
    let data: ShareRecapCardData

    var body: some View {
        Color.black
            .aspectRatio(ShareRecapCard.aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    ShareRecapCard(template: template, data: data)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity)
    }
}
