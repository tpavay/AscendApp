import SwiftUI

struct ProfileTopBar: View {
    let mode: ProfileViewMode

    var body: some View {
        HStack {
            Spacer()

            if mode == .own {
                NavigationLink {
                    AccountView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
            } else {
                Menu("Profile actions", systemImage: "ellipsis") {
                    Button("Report", systemImage: "flag") {}
                        .disabled(true)
                }
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white.opacity(0.84))
                .frame(width: 42, height: 42)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
