# Live Activity Setup Guide

## Overview

Live Activities show real-time workout stats on the lock screen and Dynamic Island during an active workout.

## What Users See

**Lock Screen:**
- Workout name and duration (large)
- Steps count
- Floors climbed
- Heart rate (if available)
- Weight equipment (if used)

**Dynamic Island (Compact):**
- Duration on left
- Steps on right

**Dynamic Island (Expanded):**
- Full stats: duration, steps, floors, SPM, heart rate, calories

## Setup Steps

### 1. Enable Live Activities in Info.plist

Add to your `Info.plist`:
```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

### 2. Create Widget Extension (if not already done)

If you don't have a widget extension:
1. File → New → Target → Widget Extension
2. Name it "AscendWidgets"
3. Check "Include Live Activity"

### 3. Add Files to Widget Target

Add these files to both the main app AND the widget extension target:
- `WorkoutActivityAttributes.swift`
- `WorkoutLiveActivityView.swift`

### 4. Register the Live Activity Widget

In your widget bundle (`AscendWidgets.swift`):
```swift
@main
struct AscendWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Other widgets...
        WorkoutLiveActivity()
    }
}
```

## Usage in App

### Starting a Live Activity

```swift
// When user starts a workout
LiveActivityManager.shared.startWorkoutActivity(
    workoutName: "Morning Climb",
    weightDescription: "20lb vest" // optional
)
```

### Updating During Workout

```swift
// Call periodically (every 1-5 seconds)
LiveActivityManager.shared.updateWorkoutActivity(
    elapsedSeconds: 1847,
    steps: 3250,
    floors: 27,
    currentHeartRate: 142,
    calories: 380,
    currentSPM: 78
)
```

### Ending the Activity

```swift
// When workout completes
LiveActivityManager.shared.endWorkoutActivity(
    finalSteps: 4500,
    finalFloors: 38,
    finalDuration: 2700
)
```

### Canceling (User Abandons Workout)

```swift
LiveActivityManager.shared.cancelActivity()
```

## Integration Points

1. **Routine Timer View** - Start activity when routine begins, update during workout
2. **Manual Workout Flow** - If you add a "Start Workout" feature
3. **HealthKit Workout Session** - Sync with HKWorkoutSession for background updates

## Notes

- Live Activities auto-end after 8 hours (iOS limit)
- Users can disable Live Activities in Settings
- Check `ActivityAuthorizationInfo().areActivitiesEnabled` before starting
- Updates are rate-limited by iOS; don't update more than every second
