#if DEBUG
import SwiftData
import SwiftUI

struct ClimbMapboxPrototypeSurface: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = GlobeViewModel()
    @State private var selectedClimb: Climb?
    @State private var didLoad = false

    private var hasMapboxToken: Bool {
        let token = (Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.hasPrefix("pk.")
    }

    var body: some View {
        ZStack {
            if hasMapboxToken {
                mapContent
            } else {
                missingTokenView
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Mapbox Prototype")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadIfNeeded()
        }
    }

    private var mapContent: some View {
        ZStack {
            ClimbMapboxPrototypeRenderer(
                scene: viewModel.mapScene,
                selectedClimbId: selectedClimb?.id,
                onSelect: { climb in
                    selectedClimb = climb
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                headerOverlay
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                Spacer()

                if let selectedClimb {
                    selectedClimbPanel(selectedClimb)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    summaryPanel
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selectedClimb?.id)
    }

    private var headerOverlay: some View {
        HStack(spacing: 10) {
            Label("Mapbox", systemImage: "map.fill")
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.black.opacity(0.58), in: Capsule())

            Text("\(viewModel.visibleClimbs.count.formatted()) climbs")
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(.white.opacity(0.86))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.black.opacity(0.46), in: Capsule())

            Spacer()

            Button {
                selectedClimb = nil
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.58), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear selected climb")
        }
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASCEND MAPBOX SURFACE")
                .font(.montserratBold(size: 11))
                .tracking(1.8)
                .foregroundStyle(.accent)

            Text("Tap a climb token to test selection, camera movement, and marker readability.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func selectedClimbPanel(_ climb: Climb) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(climb.name)
                        .font(.montserratBold(size: 20))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(climb.displayLocation.uppercased())
                        .font(.montserratSemiBold(size: 11))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                statePill(for: climb)
            }

            HStack(spacing: 12) {
                metricPill(title: "Steps", value: climb.referenceStepCount.formatted())
                metricPill(title: "Tier", value: climb.tier.rawValue.uppercased())
                metricPill(title: "State", value: climb.releaseState.rawValue.uppercased())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private func statePill(for climb: Climb) -> some View {
        let isCompleted = viewModel.isCompleted(climb)
        let label = isCompleted ? "Claimed" : (climb.isComingSoon ? "Soon" : "Open")
        let color = isCompleted ? climb.tier.color : (climb.isComingSoon ? Color.white.opacity(0.55) : Color.accent)

        return Text(label.uppercased())
            .font(.montserratBold(size: 10))
            .tracking(1.2)
            .foregroundStyle(.black.opacity(0.86))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color, in: Capsule())
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.montserratSemiBold(size: 9))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.48))

            Text(value)
                .font(.montserratBold(size: 13))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var missingTokenView: some View {
        VStack(spacing: 14) {
            Image(systemName: "map")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.accent)

            Text("Mapbox token missing")
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)

            Text("Set MBXAccessToken through MAPBOX_ACCESS_TOKEN before opening this debug surface.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(22)
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        viewModel.loadIfNeeded(modelContext: modelContext)
        selectedClimb = viewModel.firstFeaturedClimb
    }
}
#endif
