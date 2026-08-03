import SwiftUI

/// Shows what every kill switch currently resolves to and where that value came from, so a flag
/// flip in the Firebase console can be watched landing on a running build.
struct RemoteFeatureFlagsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var snapshot = RemoteFeatureFlagStore.shared.snapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                ForEach(RemoteFeatureFlag.allCases, id: \.self) { flag in
                    row(for: flag)
                }
            }
            .padding(20)
        }
        .themedBackground()
        .navigationTitle("Remote Flags")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .remoteFeatureFlagsDidChange)) { _ in
            snapshot = RemoteFeatureFlagStore.shared.snapshot
        }
        .task {
            snapshot = RemoteFeatureFlagStore.shared.snapshot
            RemoteFeatureFlagService.shared.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Server-controlled off switches")
                .font(.montserratBold(size: 20))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Text("Flip a Boolean parameter in Firebase Remote Config and this list updates without a relaunch.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
        }
    }

    private func row(for flag: RemoteFeatureFlag) -> some View {
        let isEnabled = snapshot.isEnabled(flag)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isEnabled ? Color.ascendAccent : .red)

                Text(flag.key)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Spacer()

                Text(sourceLabel(for: flag))
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
            }

            Text(flag.summary)
                .font(.montserratRegular(size: 13))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
        )
    }

    private func sourceLabel(for flag: RemoteFeatureFlag) -> String {
        switch snapshot.source(of: flag) {
        case .remote:
            return "SERVER"
        case .shippedDefault:
            return "SHIPPED DEFAULT"
        }
    }
}
