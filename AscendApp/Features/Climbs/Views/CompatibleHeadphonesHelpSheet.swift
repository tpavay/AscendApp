import SwiftUI

struct CompatibleHeadphonesHelpSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private static let appleHeadphoneCompatibilityURL = URL(string: "https://support.apple.com/en-us/102596")!

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Compatible Headphones")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text("Ascend uses headphone motion to track steps in real time during Live Climbs.")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            compatibleHeadphoneGroup(
                title: "AirPods",
                headphones: [
                    "AirPods 3",
                    "AirPods 4",
                    "AirPods 4 with Active Noise Cancellation",
                    "AirPods Pro 1",
                    "AirPods Pro 2",
                    "AirPods Pro 3",
                    "AirPods Max"
                ]
            )

            compatibleHeadphoneGroup(
                title: "Beats",
                headphones: [
                    "Beats Fit Pro",
                    "Beats Studio Pro",
                    "Beats Solo 4",
                    "Powerbeats Pro 2",
                    "Powerbeats Fit"
                ]
            )

            Link(destination: Self.appleHeadphoneCompatibilityURL) {
                Text("Don't see yours? Check Apple's current list.")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 10)
        .appSheetBackground()
        .trackOnce(screen: .compatibleHeadphonesHelp)
    }

    private func compatibleHeadphoneGroup(title: String, headphones: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.montserratSemiBold(size: 11))
                .tracking(1.1)
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.48))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(headphones, id: \.self) { headphone in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(.accent)
                            .frame(width: 5, height: 5)

                        Text(headphone)
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.76) : .black.opacity(0.66))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.04))
            )
        }
    }
}

#Preview {
    CompatibleHeadphonesHelpSheet()
        .appSheetStyle(.fitted())
}
