import SwiftData
import SwiftUI

/// The whole of connecting Apple Health after onboarding, presented full screen: connect, the
/// permission guide, the iOS sheet, then the import choice.
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
        viewModel: AppleHealthConnectViewModel = AppleHealthConnectViewModel(),
        importService: AppleHealthImportService = .shared,
        onFinished: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.importService = importService
        self.onFinished = onFinished
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            switch viewModel.step {
            case .connect:
                AppleHealthConnectView(
                    onConnect: { viewModel.showGuide() },
                    onClose: onClose
                )
                .transition(.opacity)
            case .guide:
                AppleHealthPermissionGuideView(
                    isWorking: viewModel.isWorking,
                    errorMessage: viewModel.errorMessage,
                    onBack: { viewModel.backToConnect() },
                    onConfirm: { Task { await viewModel.requestAccess() } }
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
