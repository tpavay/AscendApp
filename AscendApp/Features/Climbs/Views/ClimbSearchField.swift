import SwiftUI

/// The sheet's search field, bound to the globe view model's query.
struct ClimbSearchField: View {
    @Bindable var viewModel: GlobeViewModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            TextField("Search climbs", text: $viewModel.searchQuery)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused(isFocused)
                .onSubmit {
                    isFocused.wrappedValue = false
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else if viewModel.isRefreshingCatalog {
                ProgressView()
                    .tint(.white.opacity(0.76))
                    .scaleEffect(0.78)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isFocused.wrappedValue ? 0.1 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(isFocused.wrappedValue ? 0.2 : 0.1), lineWidth: 1)
        )
        .disabled(viewModel.availableClimbs.isEmpty)
    }
}

/// The inert search bar in the sheet that opens search mode when tapped.
struct ClimbSearchLauncher: View {
    @Bindable var viewModel: GlobeViewModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))

                Text("Search climbs")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.48))

                Spacer(minLength: 0)

                if viewModel.isRefreshingCatalog {
                    ProgressView()
                        .tint(.white.opacity(0.76))
                        .scaleEffect(0.78)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.availableClimbs.isEmpty)
        .accessibilityLabel("Search climbs")
    }
}
