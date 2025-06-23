# DOM-Specific Performance Profiling Implementation Plan

## 1. Overview

This document outlines a detailed, phased implementation plan for the **DOM-Specific Performance Profiling** feature in the Adaptive Difficulty Manager (ADM). The goal is to evolve the ADM from using a single, global performance score to a more nuanced model that can identify a user's specific strengths and weaknesses with respect to individual Difficulty of Mastery (DOM) parameters.

## 2. Guiding Principles

-   **Minimally Invasive & Incremental**: Each phase consists of small, logical changes that can be independently developed, tested, and committed.
-   **Always Buildable**: The project will be in a buildable and runnable state at the end of each phase.
-   **Feature Flag Controlled**: The new logic will be introduced behind a feature flag (`enableDomSpecificProfiling`) to allow for parallel implementation, A/B testing, and safe rollback if needed.
-   **Test-Driven**: New logic will be accompanied by corresponding unit and integration tests.

---

## 3. Phased Implementation

### Phase 1: Foundational Data Structures & Configuration

**Status**: 🟢 Completed

**Goal**: Establish the necessary data structures and configuration parameters without introducing any functional changes.

**Progress Notes**:
- Started: 6/23/2025, 3:19 PM
- Completed: 6/23/2025, 3:23 PM
- Added `DOMPerformanceProfile` struct with `PerformanceDataPoint` sub-struct (fixed Codable issue)
- Added `domPerformanceProfiles` dictionary to ADM
- Initialized profiles for all DOM types in init
- Added configuration parameters: `enableDomSpecificProfiling` (false) and `domAdaptationJitterFactor` (0.05)
- Build successful with no functional changes


**Steps**:
1.  **Create `DOMPerformanceProfile` Struct**:
    -   In `AdaptiveDifficultyManager.swift`, define the `DOMPerformanceProfile` struct as planned.
    ```swift
    struct DOMPerformanceProfile: Codable {
        let domType: DOMTargetType
        var performanceByValue: [(value: CGFloat, performance: CGFloat)] = []
        
        mutating func recordPerformance(domValue: CGFloat, performance: CGFloat) {
            performanceByValue.append((domValue, performance))
            // Simple buffer for now, can be made more sophisticated later
            if performanceByValue.count > 20 {
                performanceByValue.removeFirst()
            }
        }
    }
    ```
2.  **Integrate into `AdaptiveDifficultyManager`**:
    -   Add the new property: `private var domPerformanceProfiles: [DOMTargetType: DOMPerformanceProfile] = [:]`.
    -   In the `init` method, initialize this dictionary, creating a profile for each `DOMTargetType`.
3.  **Add Configuration Parameters**:
    -   In `GameConfiguration.swift`, add the following new parameters:
        -   `enableDomSpecificProfiling: Bool = false` (The master feature flag).
        -   `domAdaptationJitterFactor: CGFloat = 0.05` (Controls the magnitude of the random perturbation).

**Build & Test**:
-   Ensure the project builds successfully. No functional tests are needed yet, as no logic has changed.

**Commit Point**:
-   **Message**: `feat(ADM): Add data structures and config for DOM profiling`
-   **Description**: Introduces the foundational structs and configuration settings for the upcoming DOM-specific performance profiling feature. No functional changes.

---

### Phase 2: Passive Data Collection

**Status**: ⚪️ Not Started

**Goal**: Start collecting the necessary data for profiling without affecting the current adaptation logic.

**Progress Notes**:
- None


**Steps**:
1.  **Update `recordIdentificationPerformance`**:
    -   In `AdaptiveDifficultyManager.swift`, inside `recordIdentificationPerformance`, after the `overallPerformanceScore` is calculated, add a new block of code.
    -   This block will iterate through all `DOMTargetType` cases. For each `domType`, it will:
        -   Get the current absolute value of the DOM target (e.g., `currentMeanBallSpeed`).
        -   Call `domPerformanceProfiles[domType]?.recordPerformance(domValue: ..., performance: overallPerformanceScore)`.
2.  **Add Logging**:
    -   Add temporary `print` or `DataLogger` statements to verify that the `performanceByValue` arrays are being populated correctly each round.

**Build & Test**:
-   Build the project and run a session.
-   Verify through logs that the `domPerformanceProfiles` dictionary is being populated with data each round.
-   Confirm that the game's difficulty adaptation behaves exactly as it did before (as the core logic is untouched).

**Commit Point**:
-   **Message**: `feat(ADM): Implement passive data collection for DOM performance profiling`
-   **Description**: The ADM now collects performance data for each DOM parameter in the background. The core adaptation logic remains unchanged.

---

### Phase 3: Introduce Controlled Variance (Adaptation Jitter)

**Status**: ⚪️ Not Started

**Goal**: Introduce the "jitter" mechanism to de-correlate DOM movements, which is essential for effective profiling.

**Progress Notes**:
- None


**Steps**:
1.  **Modify `applyModulation`**:
    -   In `AdaptiveDifficultyManager.swift`, locate the `applyModulation` function.
    -   Just before the final `normalizedPositions[domType] = smoothedPosition` line, add the jitter logic, wrapped in an `if config.enableDomSpecificProfiling` check.
    ```swift
    var finalPosition = smoothedPosition
    if config.enableDomSpecificProfiling {
        let jitterRange = config.domAdaptationJitterFactor
        let jitter = CGFloat.random(in: -jitterRange...jitterRange)
        finalPosition += jitter
    }
    // Clamp the final position to ensure it stays within the 0.0-1.0 range
    normalizedPositions[domType] = max(0.0, min(1.0, finalPosition))
    ```
2.  **Add Unit Tests**:
    -   Create a new test case to verify that when the feature flag is enabled, the final normalized position differs slightly from the calculated smoothed position.

**Build & Test**:
-   Build and run unit tests to confirm the jitter logic works as expected.
-   Run a session with the feature flag temporarily enabled to observe the small, random variations in DOM target values.

**Commit Point**:
-   **Message**: `feat(ADM): Add controlled adaptation jitter for DOM exploration`
-   **Description**: Implements a small, random jitter to DOM adaptations when the profiling feature is enabled. This provides the necessary variance for performance attribution.

---

### Phase 4: Implement Profile-Based Adaptation Logic (Inactive)

**Status**: ⚪️ Not Started

**Goal**: Write and test the new, more sophisticated adaptation logic without activating it in the main gameplay loop.

**Progress Notes**:
- None


**Steps**:
1.  **Create `calculateDOMSpecificAdaptationSignal`**:
    -   In `AdaptiveDifficultyManager.swift`, create this new private function.
    -   It will take a `domType` as input.
    -   Inside, it will access `domPerformanceProfiles[domType]`.
    -   It will perform a simple weighted linear regression on the `performanceByValue` data to find the slope (performance gradient).
    -   It will return this slope as the adaptation signal.
2.  **Create `modulateDOMsWithProfiling`**:
    -   Create a new function that mirrors the structure of the existing `modulateDOMsWithWeightedBudget`.
    -   This new function will loop through each `DOMTargetType`, call `calculateDOMSpecificAdaptationSignal` for each, and then call `applyModulation` with the resulting signal. It will not use a shared "budget".
3.  **Add Unit Tests**:
    -   Write extensive unit tests for `calculateDOMSpecificAdaptationSignal`.
    -   Create mock `DOMPerformanceProfile` data with clear positive, negative, and neutral trends, and assert that the function returns the expected adaptation signal (+, -, or ~0).

**Build & Test**:
-   Build and run the new unit tests to ensure the regression and signal generation logic is mathematically sound.
-   The core gameplay loop is still unaffected.

**Commit Point**:
-   **Message**: `feat(ADM): Implement profile-based adaptation logic (inactive)`
-   **Description**: Adds the core functions for calculating DOM-specific adaptation signals based on performance profiles. This logic is not yet active in the main adaptation loop.

---

### Phase 5: Activation and Integration

**Status**: ⚪️ Not Started

**Goal**: Activate the new profiling system using the feature flag.

**Progress Notes**:
- None


**Steps**:
1.  **Modify `modulateDOMTargets`**:
    -   In `AdaptiveDifficultyManager.swift`, at the top of `modulateDOMTargets`, add the control flow logic.
    ```swift
    if config.enableDomSpecificProfiling {
        // Call the new logic path
        modulateDOMsWithProfiling(overallPerformanceScore: adaptiveScore)
    } else {
        // Call the existing logic path
        modulateDOMsWithWeightedBudget(...)
    }
    ```
    *Note: The function signatures will need to be aligned to make this clean.*
2.  **Integration Testing**:
    -   Thoroughly test the full gameplay loop with `enableDomSpecificProfiling` set to `true`.
    -   Use logging to observe the individual adaptation signals for each DOM and verify they are responding logically to performance.

**Build & Test**:
-   Build and perform comprehensive integration testing.
-   Compare the feel and behavior of the system with the flag on versus off.

**Commit Point**:
-   **Message**: `feat(ADM): Activate and integrate DOM-specific profiling`
-   **Description**: The new DOM-specific profiling and adaptation system is now active when the corresponding feature flag is enabled.

---

### Phase 6: Cleanup (Post-Validation)

**Status**: ⚪️ Not Started

**Goal**: Once the new system is proven to be superior and stable, remove the old code to reduce complexity.

**Progress Notes**:
- None


**Steps**:
1.  **Remove Old Logic**:
    -   Delete the old `modulateDOMsWithWeightedBudget` function and related logic (e.g., priority calculations).
2.  **Remove Feature Flag**:
    -   Remove the `enableDomSpecificProfiling` flag from `GameConfiguration` and the conditional logic from `modulateDOMTargets`.
3.  **Refactor**:
    -   Clean up any remaining code, logs, or comments related to the old system.

**Build & Test**:
-   Ensure all tests still pass after the old code is removed.

**Commit Point**:
-   **Message**: `refactor(ADM): Remove legacy adaptation logic after profiling validation`
-   **Description**: Decommissions the old budget-based adaptation system, simplifying the codebase now that the new DOM-profiling system is validated.
