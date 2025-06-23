# DOM-Specific Performance Profiling Implementation Plan (v2)

## 1. Overview

This document outlines a detailed, phased implementation plan for the **DOM-Specific Performance Profiling** feature. The goal is to evolve the ADM from using a single, global performance score to a more nuanced, persistent model that identifies and adapts to a user's specific skills over time.

## 2. Guiding Principles

-   **Minimally Invasive & Incremental**: Each phase consists of small, logical changes that can be independently developed, tested, and committed.
-   **Always Buildable**: The project will be in a buildable and runnable state at the end of each phase.
-   **Feature Flag Controlled**: The new logic will be introduced behind a feature flag (`enableDomSpecificProfiling`) for safety and A/B testing.
-   **Test-Driven**: New logic will be accompanied by corresponding unit and integration tests.
-   **Long-Term & Adaptive**: The system will build a long-term skill profile that persists across sessions but intelligently adapts to recent performance.

---

## 3. Phased Implementation

### Phase 1: Foundational Data Structures & Configuration

**Status**: 🟢 Completed

**Goal**: Establish the necessary data structures and configuration parameters.

**Progress Notes**:
- Added `DOMPerformanceProfile` struct.
- Added `domPerformanceProfiles` dictionary to ADM.
- Added `enableDomSpecificProfiling` and `domAdaptationJitterFactor` to config.
- **REVISED**: Increased the data buffer size to support a long-term skill profile.

**Steps**:
1.  **Create `DOMPerformanceProfile` Struct**:
    -   Define the struct with a `performanceByValue` array.
    -   **Crucially, set the buffer size to 200 entries** to ensure a long-term history is maintained.
    ```swift
    struct DOMPerformanceProfile: Codable {
        // ...
        var performanceByValue: [PerformanceDataPoint] = []
        
        mutating func recordPerformance(...) {
            performanceByValue.append(...)
            if performanceByValue.count > 200 { // Increased to 200
                performanceByValue.removeFirst()
            }
        }
    }
    ```
2.  **Integrate into `AdaptiveDifficultyManager`**:
    -   Add `private var domPerformanceProfiles: [DOMTargetType: DOMPerformanceProfile] = [:]`.
    -   Initialize profiles for all DOM types in `init`.

**Commit Point**:
-   **Message**: `feat(ADM): Add data structures and config for DOM profiling`
-   **Description**: Introduces foundational structs and config for DOM profiling, including a 200-entry buffer for long-term performance history.

---

### Phase 2: Passive Data Collection

**Status**: 🟢 Completed

**Goal**: Start collecting performance data for each DOM parameter without affecting adaptation logic.

**Progress Notes**:
- Implemented data collection in `recordIdentificationPerformance`.
- Verified with logging that profiles are populated.

**Steps**:
1.  **Update `recordIdentificationPerformance`**:
    -   After calculating `overallPerformanceScore`, iterate through all DOM types and call `recordPerformance` on the corresponding profile, storing the DOM's current absolute value and the player's performance.

**Commit Point**:
-   **Message**: `feat(ADM): Implement passive data collection for DOM performance profiling`
-   **Description**: The ADM now collects performance data for each DOM parameter in the background. Core adaptation logic is unchanged.

---

### Phase 3: Introduce Controlled Variance (Adaptation Jitter)

**Status**: ✅ Completed

**Goal**: Introduce a "jitter" mechanism to de-correlate DOM movements, which is essential for effective profiling.

**Progress Notes**:
- Implemented jitter logic in `applyModulation`.
- Added comprehensive unit tests confirming correct behavior.

**Steps**:
1.  **Modify `applyModulation`**:
    -   Inside an `if config.enableDomSpecificProfiling` check, add a small, random value (`+/- domAdaptationJitterFactor`) to the calculated DOM position before it's finalized.
    -   Ensure the final value is clamped between 0.0 and 1.0.

**Commit Point**:
-   **Message**: `feat(ADM): Add controlled adaptation jitter for DOM exploration`
-   **Description**: Implements a small, random jitter to DOM adaptations when profiling is enabled, providing necessary variance for performance attribution.

---

### Phase 3.5: Implement Cross-Session Persistence for Profiles

**Status**: In-progress (test suite has not been implemented)

**Goal**: Ensure the collected `domPerformanceProfiles` data is saved and loaded across sessions, enabling a true long-term skill model.

**Progress Notes**:
- Successfully implemented persistence with backward compatibility
- Added comprehensive test coverage through `ADMDOMProfilingPersistenceTests`
- Incremented state version to 2 for version tracking

**Implementation Details**:
1.  **Updated `PersistedADMState`**:
    -   Added `domPerformanceProfiles: [DOMTargetType: DOMPerformanceProfile]?` as optional field
    -   Incremented `version` from 1 to 2 for migration support
    -   Maintained backward compatibility with older saved states
2.  **Updated `saveState()`**:
    -   Now includes `domPerformanceProfiles` when creating `PersistedADMState`
3.  **Updated `loadState()`**:
    -   Checks for and loads `domPerformanceProfiles` if present
    -   Initializes fresh profiles if loading from old format
    -   Added detailed logging of loaded profile statistics
4.  **Comprehensive Test Suite**:
    -   `testDOMProfilesPersistAcrossSessions`: Verifies complete data persistence
    -   `testBackwardCompatibilityWithOldSavedState`: Ensures old saves don't crash
    -   `testLargeBufferPersistence`: Tests full 200-entry buffer save/load
    -   `testContinuityAcrossSessions`: Validates append behavior for new data

**Commit Point**:
-   **Message**: `feat(ADM): Implement persistence for DOM performance profiles`
-   **Description**: The `domPerformanceProfiles` are now saved and loaded across sessions, enabling the creation of a long-term user skill model.

---

### Phase 4: Implement Profile-Based Adaptation Logic (Inactive)

**Status**: ⚪️ Not Started

**Goal**: Write and test the new, more sophisticated adaptation logic without activating it.

**Key Design Decisions** (from team discussion):
- **Recency Weighting**: Use exponential decay with 24-hour half-life to give recent data more influence
- **Minimum Data Requirements**: 7 data points minimum before signals activate
- **Variance Threshold**: Require sufficient DOM value variance (standard deviation) to ensure reliable regression

**Steps**:
1.  **Create `calculateDOMSpecificAdaptationSignal`**:
    -   This new private function will take a `domType` as input.
    -   **Core Logic**: Perform timestamp-based weighted linear regression:
        ```swift
        // Pseudo-code for recency weighting
        let currentTime = CACurrentMediaTime()
        let weights = performanceData.map { entry in
            let ageInHours = (currentTime - entry.timestamp) / 3600.0
            return exp(-ageInHours * log(2.0) / 24.0) // 24-hour half-life
        }
        ```
    -   **Edge Case Handling**:
        -   **Guard 1 (History Size)**: If the profile contains fewer than 7 data points, return a neutral signal (`0.0`).
        -   **Guard 2 (Value Variance)**: If the standard deviation of the collected DOM values is below a minimum threshold (i.e., not enough exploration has occurred), return a neutral signal (`0.0`).
    -   Return the calculated slope as the adaptation signal.
2.  **Create `modulateDOMsWithProfiling`**:
    -   This new function will be the entry point for the new logic path.
    -   It will loop through each `DOMTargetType`, call `calculateDOMSpecificAdaptationSignal` for each, and then call `applyModulation` with the resulting signal.
3.  **Add Unit Tests**:
    -   Write extensive unit tests for `calculateDOMSpecificAdaptationSignal`.
    -   Test with mock data exhibiting clear positive, negative, and neutral trends.
    -   Test the guard clauses for history size and value variance.

**Commit Point**:
-   **Message**: `feat(ADM): Implement profile-based adaptation logic (inactive)`
-   **Description**: Adds core functions for calculating DOM-specific adaptation signals using weighted linear regression. Logic is not yet active.

---

### Phase 5: Activation and Integration

**Status**: ⚪️ Not Started

**Goal**: Activate the new profiling system using the feature flag.

**Steps**:
1.  **Modify `modulateDOMTargets`**:
    -   Add control flow: if `config.enableDomSpecificProfiling` is true, call `modulateDOMsWithProfiling`; otherwise, call the existing `modulateDOMsWithWeightedBudget`.
2.  **Integration Testing**:
    -   Thoroughly test the full gameplay loop with the feature flag enabled.
    -   Use logging to observe and verify the individual adaptation signals.

**Commit Point**:
-   **Message**: `feat(ADM): Activate and integrate DOM-specific profiling`
-   **Description**: The new DOM-specific profiling system is now active when the feature flag is enabled.

---

### Phase 6: Cleanup (Post-Validation)

**Status**: ⚪️ Not Started

**Goal**: Once the new system is proven superior, remove the old code.

**Steps**:
1.  **Remove Old Logic**: Delete `modulateDOMsWithWeightedBudget` and related priority calculations.
2.  **Remove Feature Flag**: Remove the `enableDomSpecificProfiling` flag and the conditional logic.

**Commit Point**:
-   **Message**: `refactor(ADM): Remove legacy adaptation logic after profiling validation`
-   **Description**: Decommissions the old budget-based adaptation system, simplifying the codebase.
