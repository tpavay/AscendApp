import Foundation
import Observation

/// Connecting Apple Health after onboarding: ask, show the permission guide, request, then choose
/// how workouts import.
///
/// Three steps, one decision at the end. The choice screen only exists here - onboarding connects
/// with auto-import on and never shows it - because a climber connecting later is the one who may
/// have a week of workouts already waiting and a reason to pick them by hand.
@MainActor
@Observable
final class AppleHealthConnectViewModel {
    enum Step: Equatable {
        case connect
        case guide
        case choose
    }

    private(set) var step: Step = .connect
    /// How many stair workouts Health already holds for this climber, once the choice screen shows.
    private(set) var foundCount = 0
    var choosesAutomatic = true
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let authorization: any HealthKitAuthorizationControlling
    @ObservationIgnored private let importService: AppleHealthImportService

    init(
        authorization: any HealthKitAuthorizationControlling = HealthKitAuthorizationClient.shared,
        importService: AppleHealthImportService = .shared
    ) {
        self.authorization = authorization
        self.importService = importService
    }

    /// What the choice screen says it found.
    var foundSummary: String {
        switch foundCount {
        case 0:
            return "No stair stepper workouts yet. New ones will keep coming in."
        case 1:
            return "We found 1 stair stepper workout. New ones will keep coming in."
        default:
            return "We found \(foundCount) stair stepper workouts. New ones will keep coming in."
        }
    }

    func showGuide() {
        errorMessage = nil
        step = .guide
    }

    func backToConnect() {
        errorMessage = nil
        step = .connect
    }

    /// "Got it": the iOS sheet, then a look at what Health holds. Imports nothing yet.
    func requestAccess() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        guard await authorization.requestAuthorization() else {
            errorMessage = authorization.lastPermissionErrorMessage
                ?? "Apple Health did not connect. Try again."
            return
        }

        foundCount = await importService.discoverWithoutImporting()
        step = .choose
    }

    /// "Continue": saves the choice, brings in what was found if the climber chose automatic, and
    /// reports whether it is time to open Imports.
    func confirmChoice() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        await importService.setAutoImportEnabled(choosesAutomatic)
    }
}
