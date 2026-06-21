import HealthKit
import Testing

@testable import AscendApp

struct HealthKitWorkoutReaderTests {
  @Test
  func stairWorkoutDiscoveryOnlyIncludesStairStepperActivityTypes() {
    let activityTypes = Set(HealthKitWorkoutReader.stairWorkoutActivityTypes)

    #expect(activityTypes.contains(.stairClimbing))
    #expect(activityTypes.contains(.stepTraining))
    #expect(!activityTypes.contains(.stairs))
  }
}
