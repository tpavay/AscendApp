import SwiftUI

/// Full-screen background picker: a real Camera Roll grid (photo/video) and
/// Presets. Photos permission is requested at first use by the grid itself.
struct ShareBackgroundPickerView: View {
    let title: String
    let presets: [ShareComposerPreset]
    let onPick: (ShareBackgroundSource) -> Void
    let onClose: () -> Void

    @State private var selectedTab: Tab = .cameraRoll

    private let accent = Color(red: 0.706, green: 0.8, blue: 0)

    enum Tab { case cameraRoll, presets }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabPill
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                if selectedTab == .cameraRoll {
                    ShareCameraRollGrid(onPick: onPick)
                } else {
                    presetsContent
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

    private var presetsContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(presets) { preset in
                    Button {
                        HapticsManager.shared.trigger(.lightImpact)
                        onPick(.preset(preset))
                    } label: {
                        ShareBackgroundView(source: .preset(preset), isStatic: true)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                Text(preset.displayName.uppercased())
                                    .font(.montserratSemiBold(size: 11))
                                    .tracking(1)
                                    .foregroundStyle(.white)
                                    .padding(10)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
}
