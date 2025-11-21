# Personal Records (PR) Tracking Implementation

## Overview
This document describes the comprehensive PR tracking system implemented in AscendApp. The system automatically tracks personal records when users log manual workouts or import workouts from Apple Health.

## Features

### 1. Tracked Personal Records
The system tracks the following types of personal records:
- 👟 **Most Steps** - Highest step count in a single workout
- 🪜 **Most Floors** - Highest floor count in a single workout
- ⏱️ **Longest Workout** - Longest workout duration
- ⚡ **Highest Average Pace** - Best steps/floors per minute
- 🏔️ **Highest Vertical Climb** - Most vertical distance climbed
- ❤️ **Highest Avg Heart Rate** - Highest average heart rate
- 💗 **Highest Max Heart Rate** - Highest maximum heart rate
- 🔥 **Most Calories Burned** - Most calories burned in a workout

### 2. Historical PR Tracking
- When a PR is beaten, the old record is marked as `isCurrent: false`
- Historical records are preserved in the database with a reference to the previous record they beat
- This enables future features like annotating charts with PR markers to show progress over time

### 3. Share Text Integration
When users share a workout that achieved PRs:
- Single PR: Displays as "👟 PR: Most Steps"
- Multiple PRs: Displays as a formatted list:
  ```
  Personal Records:
    • 👟 PR: Most Steps
    • ⏱️ PR: Longest Workout
    • ⚡ PR: Highest Average Pace
  ```

## Architecture

### Models

#### `PersonalRecord` (SwiftData Model)
Located: `AscendApp/Shared/Models/PersonalRecord.swift`

Properties:
- `id: UUID` - Unique identifier
- `type: PersonalRecordType` - Type of PR achieved
- `value: Double` - The record value
- `workoutId: UUID` - Reference to the workout that achieved this PR
- `achievedAt: Date` - When the PR was achieved
- `isCurrent: Bool` - Whether this is the current record or historical
- `previousRecordId: UUID?` - Reference to the previous record this one beat
- `workoutName: String` - Cached workout name for display
- `workoutDate: Date` - Cached workout date for display

#### `PersonalRecordType` (Enum)
Defines all trackable PR types with display names and emojis.

#### `PersonalRecordResult` (Struct)
Returned when checking for PRs:
- Indicates if a new record was set
- Contains previous value for comparison
- Calculates improvement percentage

#### `Workout` Model Updates
Added fields:
- `personalRecordTypes: [String]?` - Array of PR types achieved in this workout
- Computed properties:
  - `achievedPersonalRecords: [PersonalRecordType]` - Converts strings to enum
  - `hasPersonalRecords: Bool` - Quick check if workout has PRs
  - `addPersonalRecord(_ type:)` - Helper to add PRs

### Services

#### `PersonalRecordService`
Located: `AscendApp/Shared/Services/PersonalRecordService.swift`

Key Methods:
- `checkForPersonalRecords(workout:allPersonalRecords:measurementSystem:stepHeight:)` - Checks a workout for PRs without saving
- `savePersonalRecords(results:workout:modelContext:)` - Saves new PRs and marks old ones as historical
- `fetchCurrentPersonalRecords(modelContext:)` - Gets all current PRs
- `fetchAllPersonalRecords(modelContext:)` - Gets all PRs including historical
- `fetchPersonalRecords(forWorkout:modelContext:)` - Gets PRs for a specific workout

### Integration Points

#### 1. Manual Workout Creation
Location: `WorkoutFormViewModel.saveWorkout(to:)`

Flow:
1. User fills out workout form
2. Workout is saved to database
3. `checkAndSavePersonalRecords()` is called
4. PRs are checked and saved
5. Workout is updated with PR types
6. Database is saved again

#### 2. Apple Health Import
Location: `WorkoutImportService.importWorkout(_:)`

Flow:
1. HealthKit workout is fetched
2. Workout is converted to Ascend format
3. Workout is saved to database
4. `checkAndSavePersonalRecords()` is called
5. PRs are checked and saved
6. Workout is updated with PR types

#### 3. Batch HealthKit Import
Location: `HealthKitImportView.importWorkouts()`

Flow:
1. Multiple HealthKit workouts are fetched
2. For each workout:
   - Convert to Ascend format
   - Save to database
   - Check and save PRs
   - Update workout with PR types

#### 4. Share Text Formatting
Location: `WorkoutShareFormatter.workoutShareText(for:measurementSystem:stepHeight:)`

The share text now includes a PR section at the end if any PRs were achieved.

### UI Components

#### `PersonalRecordBadge`
Located: `AscendApp/Shared/Components/PersonalRecordBadge.swift`

A reusable SwiftUI view for displaying PR badges with:
- Three sizes: small, medium, large
- Gradient background (orange to red)
- Emoji + "PR" text
- Shadow for depth

#### `PersonalRecordBadgeGroup`
Displays multiple PR badges for a workout with:
- Configurable maximum visible badges
- "+N" indicator for additional PRs
- Automatic layout

## Database Schema

The `PersonalRecord` model is registered in the SwiftData schema in `AscendApp.swift`:
```swift
Schema([Workout.self, LeaderboardStats.self, PersonalRecord.self])
```

## Usage Examples

### Checking for PRs After Saving a Workout
```swift
let prResults = try checkAndSavePersonalRecords(
    for: workout,
    modelContext: modelContext
)

if !prResults.isEmpty {
    let prTypes = prResults.map { $0.type.rawValue }
    workout.personalRecordTypes = prTypes
    try modelContext.save()
}
```

### Displaying PR Badges in UI
```swift
PersonalRecordBadgeGroup(
    workout: workout,
    size: .medium,
    maxVisible: 3
)
```

### Getting All Current PRs
```swift
let currentPRs = try PersonalRecordService.fetchCurrentPersonalRecords(
    modelContext: modelContext
)
```

### Getting Historical PRs for Analysis
```swift
let allPRs = try PersonalRecordService.fetchAllPersonalRecords(
    modelContext: modelContext
)
let historicalPRs = allPRs.filter { !$0.isCurrent }
```

## Future Enhancement Ideas

### Chart Annotations
Use historical PRs to mark achievements on progress charts:
```swift
// Fetch all PRs for a specific metric
let stepPRs = allPRs.filter { 
    $0.type == .mostSteps 
}.sorted { 
    $0.achievedAt < $1.achievedAt 
}

// Plot on chart with markers
```

### PR Achievements View
Create a dedicated view showing:
- Current records in each category
- Progress over time
- Historical records that were beaten
- Time to next potential PR

### PR Notifications
Notify users when they're close to beating a PR during a workout (if real-time tracking is added).

### PR Sharing
Special share templates when a PR is achieved:
- Celebratory graphics
- Comparison to previous record
- Improvement percentage

### PR Streaks
Track consecutive workouts with at least one PR achieved.

## Testing Recommendations

1. **Manual Workout PRs**
   - Log a workout with various metrics
   - Verify PRs are created for all applicable metrics
   - Log a better workout and verify old PRs are marked historical

2. **HealthKit Import PRs**
   - Import workouts from Apple Health
   - Verify PRs are tracked correctly
   - Check batch import handles PRs properly

3. **Share Text**
   - Share a workout with no PRs (should not show PR section)
   - Share a workout with 1 PR (should show inline)
   - Share a workout with multiple PRs (should show list)

4. **Edge Cases**
   - First workout ever (all metrics should be PRs)
   - Workout with missing metrics (should only check available metrics)
   - Multiple workouts on same day with different PRs

5. **Historical Tracking**
   - Verify old PRs remain in database with isCurrent: false
   - Verify previousRecordId links are correct
   - Test fetching historical records

## Performance Considerations

- PR checking happens after workout save, not during
- Only current PRs are fetched for comparison (not historical)
- Batch imports check PRs per workout to maintain accuracy
- Database queries use predicates for efficient filtering

## Data Migration

When users update to this version:
- No existing data is modified
- First workout after update will check against no PRs (all will be new)
- Subsequent workouts will check against those baseline PRs
- This is the intended behavior (PRs start from update forward)

## Code Quality

- ✅ No linter errors
- ✅ Follows SwiftUI best practices
- ✅ Proper use of @MainActor
- ✅ Error handling with try/catch
- ✅ Type-safe enums with raw values
- ✅ Proper SwiftData model relationships
- ✅ Separation of concerns (Service layer)

