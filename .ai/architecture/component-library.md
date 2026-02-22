# Component Library - AscendApp

**Last Updated:** 2026-02-22
**Status:** Living Document - Auto-updated when components are created/modified

---

## Form Components

### FormTextField
**Location:** `Shared/Components/FormTextField.swift`
**Purpose:** Reusable text input with consistent styling across all forms
**Created:** 2026-02-22

**Features:**
- Theme-aware (uses ThemeManager + effectiveColorScheme)
- Required field indicator (asterisk in placeholder)
- Icon support
- Keyboard type configuration
- Focus management
- Max length validation
- Consistent padding (16pt), corner radius (12pt), font (.montserratRegular 16pt)

**Usage:**
```swift
FormTextField(
    label: "Email",
    isRequired: true,
    icon: "envelope",
    keyboardType: .emailAddress,
    text: $email,
    focusedField: $focusedField,
    fieldIdentifier: .email,
    maxLength: 100
)
```

### FormTextEditor
**Location:** `Shared/Components/FormTextField.swift`
**Purpose:** Multi-line text input variant

**Features:**
- Same styling as FormTextField
- Configurable line limits (default 3-6)
- Vertical expansion
- Max length validation

**Usage:**
```swift
FormTextEditor(
    label: "Description",
    isRequired: false,
    lineLimit: 3...6,
    text: $description,
    focusedField: $focusedField,
    fieldIdentifier: .description
)
```

### FormButton
**Location:** `Shared/Components/FormButton.swift`
**Purpose:** Button-style form field for pickers, selectors, and actions

**Features:**
- Consistent with FormTextField styling
- Icon support
- Shows selected value or placeholder
- Chevron indicator
- Theme-aware

**Usage:**
```swift
FormButton(
    label: "Select Date",
    isRequired: true,
    icon: "calendar",
    value: selectedDate,
    action: { showingDatePicker = true }
)
```

### FormSection
**Location:** `Shared/Components/FormSection.swift`
**Purpose:** Consistent section headers for forms

**Features:**
- Uppercase title styling
- Theme-aware text color
- Consistent spacing (12pt gap)
- Small font (.montserratMedium 12pt)

**Usage:**
```swift
FormSection(title: "Health Metrics") {
    VStack(spacing: 12) {
        FormTextField(...)
        FormTextField(...)
    }
}
```

---

## Badge Components

### PersonalRecordBadge
**Location:** `Shared/Components/PersonalRecordBadge.swift`
**Purpose:** Display personal record indicators on workouts

**Features:**
- Size variants (small, medium, large)
- Theme-aware colors
- Icon + text or icon-only modes

### WeightIndicatorBadge
**Location:** `Shared/Components/WeightIndicatorBadge.swift`
**Purpose:** Show weight equipment used in workouts

---

## Data Display Components

### LoadablePhotoView
**Location:** `Shared/Components/LoadablePhotoView.swift`
**Purpose:** Display photos with loading states

**Features:**
- Async image loading
- Loading spinner
- Error state handling
- Aspect ratio preservation

---

## Card Components

### ThisWeekCard
**Location:** `Features/Home/Components/ThisWeekCard.swift`
**Purpose:** Display weekly workout summary

### RoutineCard
**Location:** `Features/Routines/Components/RoutineCard.swift`
**Purpose:** Display routine in lists

---

## View Components

### PhotoGalleryView
**Location:** `Shared/Views/PhotoGalleryView.swift`
**Purpose:** Photo/video selection and display

### DateTimePickerView
**Location:** `Shared/Views/DateTimePickerView.swift`
**Purpose:** Custom date/time picker with styling

### EffortRatingView
**Location:** `Features/Workouts/Views/EffortRatingView.swift`
**Purpose:** Select workout effort rating (1-10)

### ConfirmationView
**Location:** `Shared/Views/ConfirmationView.swift`
**Purpose:** Reusable confirmation dialogs with loading states

---

## Weight Entry Components

### WeightEntryView
**Location:** `Features/Workouts/Components/WeightEntryView.swift`
**Purpose:** Complex compound component for entering equipment weights

**Features:**
- Toggle-based enable/disable
- Conditional content expansion
- Animation support
- Measurement system aware

---

## Background & Theme Components

### ThemedBackground
**Location:** `Shared/Views/ThemedBackground.swift`
**Purpose:** Consistent app background

**Features:**
- Dark: Gradient (night → jetLighter)
- Light: White
- Used via `.themedBackground()` modifier

### ThemeAwareModifier
**Purpose:** Apply effective color scheme to views
**Usage:** `.themeAware()`

---

## Component Creation Guidelines

When creating a new component, ensure:

1. **Add to this document** with:
   - Location, purpose, creation date
   - Key features
   - Usage example
   - Any special considerations

2. **Follow established patterns:**
   - Use ThemeManager + effectiveColorScheme
   - Support both light/dark modes
   - Use Montserrat fonts
   - Include SwiftUI previews (light & dark)
   - Handle edge cases (empty, loading, error)

3. **Make it reusable:**
   - Generic and configurable
   - No hardcoded values (use parameters)
   - Clear, descriptive naming
   - Appropriate default values

4. **Document complex components:**
   - Add code comments for non-obvious logic
   - Include usage examples in header comments

---

## Component Naming Conventions

- Views: `[Name]View` (e.g., DateTimePickerView)
- Components: `[Name][Type]` (e.g., PersonalRecordBadge)
- Dialogs/Sheets: `[Name]Dialog` or `[Name]Sheet`
- Cards: `[Name]Card`
- Form inputs: `Form[Type]` (e.g., FormTextField)

---

**Auto-Update Policy:** When Claude creates/modifies a component, this document is automatically updated with the new pattern.
