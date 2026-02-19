# Ascend Widgets Setup Guide

## Creating the Widget Extension in Xcode

1. **Open the project in Xcode**

2. **Add Widget Extension Target:**
   - File → New → Target
   - Search for "Widget Extension"
   - Name it "AscendWidgets"
   - Uncheck "Include Configuration Intent" (we'll use static config first)
   - Click Finish

3. **Set up App Group:**
   - Select the main "AscendApp" target → Signing & Capabilities
   - Click "+ Capability" → App Groups
   - Add a new group: `group.com.ascendapp.shared`
   - Select the "AscendWidgets" target and add the same App Group

4. **Copy Widget Files:**
   - Replace the generated widget files with the ones in this folder
   - Make sure to add them to the AscendWidgets target

5. **Set up Shared Data:**
   - The widget reads from UserDefaults with the App Group suite
   - The main app needs to write workout stats to this shared container

## Files in this folder:

- `AscendWidgets.swift` - Main widget entry point
- `StreakWidget.swift` - Shows current workout streak
- `WeeklyProgressWidget.swift` - Shows weekly step/floor progress
- `SharedDataManager.swift` - Handles data sharing between app and widget

## Data Flow:

1. Main app saves workout → Updates shared UserDefaults
2. Widget reads from shared UserDefaults
3. Widget timeline refreshes periodically or on app updates
