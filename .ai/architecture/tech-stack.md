# Tech Stack - AscendApp

**Last Updated:** 2026-02-22
**Status:** Living Document - Auto-updated when technologies change

---

## Platform
- **iOS:** SwiftUI app for iPhone
- **Minimum Version:** iOS 17+
- **Language:** Swift
- **IDE:** Xcode

---

## UI Framework

### SwiftUI
**Version:** Latest (iOS 17+)

**Key Features Used:**
- NavigationStack for navigation
- Observable macro for ViewModels (replaces @StateObject)
- FocusState for keyboard management
- Task for async operations
- PhotosUI for photo picking
- SwiftData for persistence

**Patterns:**
- MVVM architecture
- Declarative UI composition
- State-driven rendering

---

## Data Layer

### SwiftData
**Purpose:** Local persistence (primary data store)

**Features:**
- @Model macro for entities
- ModelContext for CRUD operations
- @Query for reactive data fetching
- Automatic change tracking

**Models:**
- Workout
- Photo
- Routine
- WeightConfiguration

### Firebase
**Purpose:** Remote backup and cross-device sync

**Services Used:**
- Firestore: Document storage
- Firebase Storage: Media (photos/videos)
- Firebase Auth: User authentication

**Pattern:** Local-first with background sync

---

## Third-Party Integrations

### Apple HealthKit
**Purpose:** Read/write health and workout data

**Data Accessed:**
- Heart rate
- Workout sessions
- Steps climbed
- Floors climbed

**Permission:** User opt-in required

## Managers & Services

### ThemeManager
**Purpose:** Centralized theme management
**Pattern:** Singleton, Observable
**Features:**
- Three modes: system, light, dark
- Persists to UserDefaults
- Provides effectiveColorScheme()

### SettingsManager
**Purpose:** App settings and preferences
**Pattern:** Singleton, Observable
**Settings:**
- Preferred workout metric (steps/floors)
- Measurement system (imperial/metric)
- Theme preference

### HapticsManager
**Purpose:** Haptic feedback
**Pattern:** Singleton
**Usage:** User interaction confirmation

### PhotoService
**Purpose:** Photo/video upload and management
**Features:**
- Firebase Storage integration
- Async upload
- Progress tracking

---

## Design System

### Fonts
**Montserrat Family:**
- MontserratBold
- MontserratSemiBold
- MontserratMedium
- MontserratRegular
- MontserratLight
- MontserratItalic

**Access via:** Font extensions (.montserratBold(size:), etc.)

### Colors
**Named Colors (Assets.xcassets):**
- Jet (#1F1F1F) - Dark background
- JetDarker (#141414)
- JetLighter (#292929)
- Night - Secondary dark
- NightLighter
- AccentColor (#86D30A) - Bright green
- customGray (#888888)
- darkGray (#333333)

**Gradients:**
- Intensity gradients (veryLight → veryHard)
- Background gradients (night → jetLighter)

---

## Build Configuration

### Dependencies
- SwiftData (built-in)
- PhotosUI (built-in)
- Firebase SDK
- StoreKit (for potential future features)

### Build Targets
- Main app target: AscendApp
- Potential watch app (future)

---

## Development Tools

### Version Control
- Git
- GitHub repository: tpavay/AscendApp

### CI/CD
- GitHub Actions for workflows
- Staging environment

---

## App Capabilities

### Required Capabilities
- HealthKit integration
- Photo library access
- Camera access (for workout media)
- Network access (Firebase sync)

### Privacy
- Privacy Policy in-app (PrivacyPolicyView)
- User consent for HealthKit
- User consent for photo access
- Local-first data (works offline)

---

## Performance Considerations

### Optimization Strategies
- Lazy loading for lists (LazyVStack)
- Async image loading (LoadablePhotoView)
- Background sync (non-blocking)
- SwiftUI view optimization (avoid unnecessary re-renders)
- Efficient @Query usage

### Memory Management
- Automatic reference counting (ARC)
- Weak references for delegates
- Task cancellation for async operations

---

## Security Measures

### Data Protection
- Keychain for sensitive tokens
- Encrypted Firebase communication
- No PII in logs
- Secure file storage

### Input Validation
- Text field max lengths
- Numeric input filtering
- Email validation
- File type validation (photos/videos only)

---

## Future Considerations

### Potential Additions
- Apple Watch app
- Widgets
- SharePlay integration
- Advanced analytics
- Social features

### Scalability
- Architecture supports horizontal scaling
- Component-based for easy feature addition
- Local-first supports offline scenarios

---

**Auto-Update Policy:** This document is updated when:
- New dependencies are added
- Technologies are upgraded
- Architecture significantly changes
- New integrations are added
