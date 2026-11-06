import SwiftUI

/// Settings -> Weekly target: set it, change it, or clear it. Clearing removes the ring from Home
/// and leaves the week streak, which never depended on a target.
struct WeeklyTargetSettingsView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @State private var selection: WeeklyTarget?
    @State private var hasLoaded = false

    private let service = WeeklyTargetService()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Set a target if you want one. Hit your days and close your week.")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                ForEach(WeeklyTarget.validDays, id: \.self) { days in
                    if let target = WeeklyTarget(days: days) {
                        row(title: target.summary, detail: target.tier.title.capitalized, isSelected: selection == target) {
                            choose(target)
                        }
                    }
                }

                row(title: "No target", detail: "No ring", isSelected: hasLoaded && selection == nil) {
                    choose(nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .themedBackground()
        .navigationTitle("Weekly target")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .task {
            guard let userId = authVM.user?.uid else { return }
            selection = service.localTarget(for: userId)
            hasLoaded = true
        }
        .trackOnce(screen: .weeklyTargetSettings)
    }

    private func choose(_ target: WeeklyTarget?) {
        guard let userId = authVM.user?.uid else { return }
        selection = target
        HapticsManager.shared.trigger(.selection)
        Task { await service.save(target, for: userId) }
    }

    private func row(title: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.montserratSemiBold)
                    Text(detail)
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.accent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.jetLighter.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Color.accent.opacity(0.6) : .white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
