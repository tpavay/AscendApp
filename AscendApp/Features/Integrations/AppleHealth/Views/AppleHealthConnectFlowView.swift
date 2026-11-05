import SwiftData
import SwiftUI

/// The whole of connecting Apple Health after onboarding, presented full screen: connect, the iOS
/// sheet, then the import choice.
///
/// Opens on the choice when the app ended there before the climber picked.
///
/// `onFinished` runs after the choice is saved and the cover has closed, which is where the caller
/// opens Imports. Closing early - the X, Not now - calls only `onClose`, and nothing is saved.
struct AppleHealthConnectFlowView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: AppleHealthConnectViewModel
    private let importService: AppleHealthImportService
    let onFinished: () -> Void
    let onClose: () -> Void

    init(
        viewModel: AppleHealthConnectViewModel? = nil,
        importService: AppleHealthImportService = .shared,
        onFinished: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel ?? AppleHealthConnectViewModel(importService: importService))
        self.importService = importService
        self.onFinished = onFinished
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            switch viewModel.step {
            case .connect:
                AppleHealthConnectView(
                    isWorking: viewModel.isWorking,
                    errorMessage: viewModel.errorMessage,
                    onConnect: { Task { await viewModel.requestAccess() } },
                    onClose: onClose
                )
                .transition(.opacity)
            case .choose:
                AppleHealthImportChoiceView(
                    choosesAutomatic: $viewModel.choosesAutomatic,
                    summary: viewModel.foundSummary,
                    isWorking: viewModel.isWorking,
                    onContinue: {
                        Task {
                            await viewModel.confirmChoice()
                            onFinished()
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.step)
        .background(Color.black.ignoresSafeArea())
        .task { importService.configure(modelContext: modelContext) }
    }
}
