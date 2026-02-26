# Architectural Patterns - AscendApp

**Last Updated:** 2026-02-22
**Status:** Living Document - Auto-updated as patterns evolve

---

## App Architecture

### Feature-Based Structure
```
AscendApp/
├── Features/              # Feature modules
│   ├── Account/
│   ├── Home/
│   ├── Routines/
│   ├── Workouts/
│   └── [Feature]/
│       ├── Models/
│       ├── ViewModels/
│       ├── Views/
│       ├── Components/    # Feature-specific components
│       └── Services/
├── Shared/               # Shared across features
│   ├── Components/       # Reusable UI components
│   ├── Views/           # Shared screens/containers
│   ├── Extensions/      # Swift extensions
│   ├── Managers/        # Singleton managers
│   ├── Models/          # Data models
│   └── Services/        # Business logic
└── Resources/           # Assets, fonts, etc.
```

**Principle:** Features are self-contained; shared code goes in Shared/

---

## Data Layer Patterns

### Local-First Architecture
**Pattern:** All data operations happen locally first, sync in background

```swift
// ✅ GOOD: Local-first
func saveWorkout() async {
    // 1. Save locally (immediate)
    await modelContext.insert(workout)

    // 2. Sync to cloud (background, non-blocking)
    Task {
        await syncService.upload(workout)
    }
}

// ❌ BAD: Network-first
func saveWorkout() async {
    // Blocks UI waiting for network
    await api.uploadWorkout(workout)
    modelContext.insert(workout)
}
```

### SwiftData + Firebase Pattern
- **SwiftData:** Local persistence, source of truth
- **Firebase:** Remote backup, cross-device sync
- **Sync Strategy:** Optimistic updates, eventual consistency

### Data Flow
```
User Action → ViewModel → Local DB (SwiftData) → UI Update
                              ↓
                         Background Sync (Firebase)
```

---

## View Architecture Patterns

### MVVM (Model-View-ViewModel)
**Standard pattern for features**

```swift
// Model (SwiftData)
@Model class Workout { ... }

// ViewModel (@Observable)
@Observable class WorkoutFormViewModel {
    var workoutName: String = ""
    var isValid: Bool { ... }

    func save() async throws { ... }
}

// View (SwiftUI)
struct WorkoutFormView: View {
    @State private var viewModel = WorkoutFormViewModel()
    var body: some View { ... }
}
```

**Guidelines:**
- ViewModels handle business logic, validation, API calls
- Views handle UI, layout, user interaction
- Models are just data (SwiftData models)

### State Management
**Pattern:** Use appropriate state management for scope

- `@State`: Local view state
- `@Binding`: Pass state to child views
- `@Environment`: Shared environment values (modelContext, dismiss, colorScheme)
- `@Observable`: ViewModels and managers (replaces @StateObject/@ObservedObject)
- `@FocusState`: Keyboard/focus management

---

## Theming System

### ThemeManager Pattern
**Centralized theme management**

```swift
// 1. Access ThemeManager
@State private var themeManager = ThemeManager.shared

// 2. Get system color scheme
@Environment(\.colorScheme) private var colorScheme

// 3. Calculate effective scheme
private var effectiveColorScheme: ColorScheme {
    themeManager.effectiveColorScheme(for: colorScheme)
}

// 4. Use in views
.foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
```

**Never hardcode light/dark colors directly**

### Color System
- **Named colors:** Jet, JetDarker, JetLighter, Night, AccentColor
- **Semantic usage:** Use named colors for consistency
- **Opacity pattern:**
  - Text: `.white` / `.black` (100% primary)
  - Secondary: `.white.opacity(0.6)` / `.gray`
  - Tertiary: `.white.opacity(0.5)` / `.gray.opacity(0.7)`
  - Backgrounds: `.white.opacity(0.05)` (dark) / `.gray.opacity(0.06)` (light)
  - Borders: `.white.opacity(0.1)` (dark) / `.gray.opacity(0.15)` (light)

### Typography System
**Montserrat font family**

```swift
.montserratBold(size: 28)      // Headers
.montserratSemiBold(size: 20)  // Subheaders
.montserratMedium(size: 17)    // Labels
.montserratRegular(size: 16)   // Body text
.montserratLight               // Light emphasis
```

**Always use custom fonts, not system fonts**

---

## Styling Patterns

### Spacing System
- **Between sections:** 24pt
- **Between rows:** 12pt
- **Within elements:** 8-12pt
- **Component padding:** 16pt (standard)
- **Card padding:** 20pt outer, 16pt inner

### Corner Radius System
- **Cards/containers:** 16pt
- **Form fields:** 12pt
- **Badges:** 6-8pt
- **Buttons:** 8-12pt

### Component Composition
**Build complex UIs from simple components**

```swift
// ✅ GOOD: Composed from reusable parts
FormSection(title: "Details") {
    VStack(spacing: 12) {
        FormTextField(label: "Name", text: $name)
        FormButton(label: "Date", value: date, action: { ... })
    }
}

// ❌ BAD: Monolithic inline styling
VStack {
    Text("DETAILS").font(...).foregroundStyle(...)
    TextField(...).padding(...).background(...)
    Button(...) { HStack { ... }.padding(...).background(...) }
}
```

---

## Navigation Patterns

### NavigationStack Pattern
**Standard navigation for hierarchical flows**

```swift
NavigationStack {
    ListView()
}
.sheet(isPresented: $showingDetail) {
    DetailView()
}
```

### Modal Presentation
- **Sheets:** For forms, editors, secondary content
- **fullScreenCover:** For major flows (onboarding, camera)
- **Detents:** Use `.presentationDetents()` for partial sheets

---

## Error Handling Patterns

### User-Facing Errors
```swift
// Display user-friendly messages
@State private var errorMessage: String?

.alert("Error", isPresented: .constant(errorMessage != nil)) {
    Button("OK") { errorMessage = nil }
} message: {
    Text(errorMessage ?? "")
}
```

### Logging Pattern
```swift
// Development logging only
#if DEBUG
print("🐛 Debug info: \(value)")
#endif

// Never log sensitive data (PII, tokens, passwords)
```

---

## Performance Patterns

### Lazy Loading
**Use lazy loading for lists and expensive operations**

```swift
// ✅ GOOD: Lazy
ScrollView {
    LazyVStack {
        ForEach(items) { item in
            ItemView(item: item)
        }
    }
}

// ❌ BAD: Eager loading large lists
ScrollView {
    VStack {  // Renders all items immediately
        ForEach(items) { item in ... }
    }
}
```

### Async/Await Pattern
**Use structured concurrency for async operations**

```swift
Task {
    do {
        let result = try await service.fetch()
        await MainActor.run {
            self.data = result
        }
    } catch {
        await MainActor.run {
            self.errorMessage = error.localizedDescription
        }
    }
}
```

---

## Security Patterns

### Input Validation
**Always validate user input**

```swift
// ✅ GOOD: Validated
var isValid: Bool {
    !name.isEmpty &&
    name.count <= 50 &&
    email.contains("@")
}

// Sanitize before saving
let sanitized = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
```

### Secrets Management
- **Never commit:** API keys, tokens, .env files
- **Use:** Keychain for sensitive data
- **Environment variables:** For configuration (but not secrets in git)

---

## Animation Patterns

### Standard Durations
- **Content animations:** `.easeInOut(duration: 0.2)`
- **Theme transitions:** `.easeInOut(duration: 0.3)`
- **Transitions:** `.opacity.combined(with: .move(edge:))`

### Conditional Content
```swift
if isExpanded {
    DetailContent()
        .transition(.opacity.combined(with: .move(edge: .top)))
}
.animation(.easeInOut(duration: 0.2), value: isExpanded)
```

---

## Testing Patterns

### SwiftUI Previews
**Always include previews for components**

```swift
#Preview {
    ComponentView()
        .padding()
        .themedBackground()
}

#Preview("Dark Mode") {
    ComponentView()
        .preferredColorScheme(.dark)
}
```

---

## Accessibility Patterns

### Semantic UI
- Use semantic components (Button, TextField) over custom gestures
- Provide meaningful labels for icons
- Support Dynamic Type with relative font sizing

---

**Auto-Update Policy:** This document evolves as new architectural patterns are established or existing patterns are improved.
