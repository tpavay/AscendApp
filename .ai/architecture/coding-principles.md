# Coding Principles - AscendApp

**Last Updated:** 2026-02-22
**Status:** Living Document - Auto-updated by Claude

---

## Core Principles (Apply to ALL Code)

### 1. DRY (Don't Repeat Yourself)
**Rule:** If code/styling/logic appears 2+ times, extract it.

**When to extract:**
- ✅ Same UI pattern in 2+ places → Reusable component
- ✅ Same logic in 3+ places → Helper function/service
- ✅ Same styling pattern → Shared modifier or component
- ✅ Same data transformation → Model extension or utility

**Example:**
```swift
// ❌ BAD - Duplicated styling
TextField(...).padding(16).background(RoundedRectangle...)
TextField(...).padding(16).background(RoundedRectangle...)

// ✅ GOOD - Reusable component
FormTextField(label: "Name", text: $name)
FormTextField(label: "Email", text: $email)
```

### 2. Reusability
**Rule:** Build components and utilities that work across the entire app.

- Components should be **generic** and **configurable**
- Use parameters/bindings for customization, not hardcoded values
- Place in appropriate directory (Shared/Components/ for app-wide, Features/X/Components/ for feature-specific)

### 3. Scalability
**Rule:** Code should handle growth without refactoring.

- Use lazy loading for lists/data
- Avoid N+1 queries
- Design components to handle edge cases (empty states, errors, loading)
- Consider performance implications of SwiftUI view updates

### 4. Maintainability
**Rule:** Code should be easy to understand and modify 6 months later.

- Clear naming (no abbreviations unless standard)
- Single responsibility per component/function
- Comments only where logic isn't self-evident
- Consistent patterns across codebase

### 5. Local-First Data
**Rule:** App should work offline; sync is enhancement.

- Use SwiftData for local persistence
- All mutations happen locally first
- Background sync to Firebase when available
- Handle conflicts gracefully
- Never block UI on network requests

### 6. Security
**Rule:** Protect user data and prevent vulnerabilities.

**Never commit:**
- API keys, secrets, credentials
- .env files, config with sensitive data
- User PII in logs or analytics

**Always:**
- Validate user input (especially text fields, file uploads)
- Sanitize data before display (prevent injection)
- Use secure storage for tokens (Keychain)
- Encrypt sensitive data at rest
- Follow OWASP guidelines for mobile

### 7. Consistency
**Rule:** Follow established patterns unless there's a compelling reason not to.

- Use ThemeManager + effectiveColorScheme for all theme-aware UI
- Use Montserrat font family (.montserratRegular, .montserratBold, etc.)
- Follow existing file structure and naming conventions
- Match existing component patterns

---

## When to Create New Components

### Required Conditions (any one triggers extraction):
1. **Duplication:** Pattern used 2+ times
2. **Complexity:** Logic/UI too complex for inline code
3. **Reusability:** Could be used elsewhere in app
4. **Clarity:** Extraction improves readability

### Component Checklist:
- [ ] Named clearly and descriptively
- [ ] Generic and configurable (parameters, not hardcoded)
- [ ] Follows theming system (ThemeManager)
- [ ] Handles edge cases (empty, loading, error states)
- [ ] Added to component library documentation
- [ ] Includes preview for testing

---

## Code Review Standards

Before committing, verify:
- [ ] No duplication - patterns extracted to reusable components
- [ ] Follows DRY principles
- [ ] Uses existing components where applicable
- [ ] Theme-aware (uses effectiveColorScheme, not hardcoded colors)
- [ ] Secure (no secrets, validates input, sanitizes output)
- [ ] Performant (no N+1 queries, uses lazy loading)
- [ ] Local-first (works offline)
- [ ] Maintainable (clear naming, single responsibility)
- [ ] Tested edge cases (empty, loading, error states)

---

## Proactive Refactoring

**Always look for opportunities to improve existing code:**

When touching a file, check for:
- Duplicated styling → Extract to component
- Hardcoded values → Make configurable
- Inconsistent patterns → Standardize
- Performance issues → Optimize
- Security vulnerabilities → Fix immediately

**Don't just solve the immediate problem - improve the architecture.**

---

## Examples

### ✅ Good: Extracted Reusable Component
```swift
// Created FormTextField component once
// Used everywhere consistently
FormTextField(label: "Name", isRequired: true, text: $name)
FormTextField(label: "Email", isRequired: true, text: $email)
```

### ❌ Bad: Duplicated Styling
```swift
TextField("Name", text: $name)
    .padding(16)
    .background(RoundedRectangle(cornerRadius: 12)...)
    .font(.montserratRegular(size: 16))

TextField("Email", text: $email)
    .padding(16)
    .background(RoundedRectangle(cornerRadius: 12)...)
    .font(.montserratRegular(size: 16))
```

---

**Note:** This document is automatically updated when architectural patterns change or new principles emerge.
