import Foundation
import Testing
import UserNotifications
@testable import AscendApp

/// Screen 12's copy and what its two buttons do.
@MainActor
struct NotificationPrimerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func catalog() throws -> UnlockCatalog {
        let json = """
        {
          "version": 1,
          "events": [
            {"id": "halloween-2026", "title": "Halloween", "monthName": "October",
             "startsOn": "2026-10-01", "endsBefore": "2026-11-01", "showcase": ["pumpkin_classic"]},
            {"id": "thanksgiving-2026", "title": "Thanksgiving", "monthName": "November",
             "startsOn": "2026-11-01", "endsBefore": "2026-12-01", "showcase": ["pumpkin_pie"]}
          ],
          "items": [
            {"id": "pumpkin_classic", "slot": "carry", "shape": "pumpkin_classic", "status": "live",
             "earn": {"path": "event", "event": "halloween-2026", "metric": "visits", "threshold": 1}},
            {"id": "pumpkin_pie", "slot": "carry", "shape": "pumpkin_pie", "status": "live",
             "earn": {"path": "event", "event": "thanksgiving-2026", "metric": "climbs", "threshold": 1}}
          ]
        }
        """
        return try JSONDecoder().decode(UnlockCatalog.self, from: Data(json.utf8))
    }

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private func make(target: Int?, minutes: Int? = nil, catalog: UnlockCatalog, now: Date? = nil) -> NotificationPrimerContent {
        NotificationPrimerContent.make(
            weeklyTargetDays: target,
            usualClimbMinutes: minutes,
            catalog: catalog,
            now: now ?? date(11, 4),
            calendar: calendar
        )
    }

    // MARK: - Copy

    @Test
    func withATargetAllThreeExamplesAndTheTargetClauseShow() throws {
        let content = make(target: 3, catalog: try catalog())

        #expect(content.examples.map(\.kind) == [.weeklyTarget, .gearDrop, .climbDrop])
        #expect(content.body.contains("short of your weekly target"))
        #expect(content.examples[0].title == "One climb from your target")
        #expect(content.examples[0].body == "2 of 3 days done this week. 20 minutes gets it done.")
    }

    @Test
    func withoutATargetTheTargetExampleAndClauseLeave() throws {
        let content = make(target: nil, catalog: try catalog())

        #expect(content.examples.map(\.kind) == [.gearDrop, .climbDrop])
        #expect(!content.body.contains("target"))
        #expect(content.body == "A nudge when new gear drops, when new climbs open, and before any trial ends.")
    }

    @Test
    func theGearExampleNamesTheEventThatIsOnNow() throws {
        let gear = try #require(make(target: nil, catalog: try catalog()).examples.first { $0.kind == .gearDrop })

        #expect(gear.title == "November gear just dropped")
        #expect(gear.when == "Nov 1")
        #expect(gear.body == "New items for your athlete. Your first climb this month unlocks one.")
        #expect(gear.thumbnailName == "Gear/pumpkin_pie")
    }

    @Test
    func theGearExampleDoesNotPromiseAFirstClimbItemTheEventLacks() throws {
        // October's only item is the visit item, so the first climb unlocks nothing.
        let gear = try #require(make(target: nil, catalog: try catalog(), now: date(10, 15)).examples.first { $0.kind == .gearDrop })

        #expect(gear.title == "October gear just dropped")
        #expect(gear.body == "New items for your athlete. Climb this month to earn them.")
    }

    @Test
    func aMonthBetweenEventsNamesTheLatestOneThatOpened() throws {
        let gear = try #require(make(target: nil, catalog: try catalog(), now: date(12, 20)).examples.first { $0.kind == .gearDrop })
        #expect(gear.title == "November gear just dropped")
    }

    @Test
    func noOpenedEventLeavesTheGearExampleOut() throws {
        let content = make(target: nil, catalog: try catalog(), now: date(9, 1))
        #expect(content.examples.map(\.kind) == [.climbDrop])
        let empty = make(target: nil, catalog: .empty)
        #expect(empty.examples.map(\.kind) == [.climbDrop])
    }

    @Test
    func theClimbDropExampleReplacesTheTrialExample() throws {
        let content = make(target: 3, catalog: try catalog())
        let climb = try #require(content.examples.first { $0.kind == .climbDrop })

        #expect(climb.title == "New climb open")
        #expect(climb.body == "Burj Khalifa just opened. Be the first to the top.")
        #expect(!content.examples.contains { $0.title.lowercased().contains("free week") })
    }

    @Test
    func nothingOnTheScreenUsesTheDesignsRetiredOrBannedWording() throws {
        for target in [nil, 1, 3, 7] as [Int?] {
            let content = make(target: target, catalog: try catalog())
            let lines = [content.body, content.accessibilityHeadline]
                + content.examples.flatMap { [$0.title, $0.body, $0.when] }

            for line in lines {
                let lowered = line.lowercased()
                #expect(!line.contains("\u{2014}"), "\(line)")
                #expect(!lowered.contains("that's it"), "\(line)")
                for word in ["race", "live", "field"] {
                    #expect(!lowered.contains(word), "\(line)")
                }
            }
        }
    }

    // MARK: - Buttons

    private func coordinator(target: Int? = 3) -> OnboardingV3Coordinator {
        let suite = "notification-primer-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(
            store: PreAuthOnboardingStore(userDefaults: defaults),
            startingAt: .notificationPrimer
        )
        coordinator.update {
            $0.weeklyTargetDays = target
            $0.usualClimbMinutes = 30
        }
        return coordinator
    }

    private struct Calls {
        var asked = 0
        var declined = 0
        var tracked: [PreAuthOnboardingNotificationChoice] = []
    }

    private final class Recorder {
        var calls = Calls()
    }

    private func viewModel(
        _ coordinator: OnboardingV3Coordinator,
        recorder: Recorder,
        answer: UNAuthorizationStatus
    ) throws -> NotificationPrimerViewModel {
        let catalog = try catalog()
        return NotificationPrimerViewModel(
            coordinator: coordinator,
            loadCatalog: { catalog },
            requestAuthorization: { recorder.calls.asked += 1; return answer },
            declineNotifications: { recorder.calls.declined += 1 },
            track: { recorder.calls.tracked.append($0) }
        )
    }

    @Test
    func turnOnAsksIOSAndMovesOn() async throws {
        let coordinator = coordinator()
        let recorder = Recorder()
        let model = try viewModel(coordinator, recorder: recorder, answer: .authorized)

        await model.turnOn()

        #expect(recorder.calls.asked == 1)
        #expect(recorder.calls.tracked == [.allowed])
        #expect(coordinator.answers.notificationChoice == .allowed)
        #expect(coordinator.step == .auth)
    }

    @Test
    func aDeniedPromptRecordsTheDenialAndStillMovesOn() async throws {
        let coordinator = coordinator()
        let recorder = Recorder()
        let model = try viewModel(coordinator, recorder: recorder, answer: .denied)

        await model.turnOn()

        #expect(coordinator.answers.notificationChoice == .denied)
        #expect(coordinator.step == .auth)
    }

    @Test
    func notNowNeverAsksIOSAndMovesOn() async throws {
        let coordinator = coordinator()
        let recorder = Recorder()
        let model = try viewModel(coordinator, recorder: recorder, answer: .authorized)

        await model.notNow()

        #expect(recorder.calls.asked == 0)
        #expect(recorder.calls.declined == 1)
        #expect(recorder.calls.tracked == [.skipped])
        #expect(coordinator.answers.notificationChoice == .skipped)
        #expect(coordinator.step == .auth)
    }
}
