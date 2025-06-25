# ADM DOM-Specific Profiling Implementation Plan

This document outlines the phased implementation of the DOM-Specific Performance Profiling feature.

---

### Phase 1: Foundational Data Structures (COMPLETE)
- [x] Define `DOMPerformanceProfile` struct.
- [x] Integrate `domPerformanceProfiles: [DOMTargetType: DOMPerformanceProfile]` into `AdaptiveDifficultyManager`.
- [x] Update `PersistedADMState` to include `domPerformanceProfiles`.

### Phase 2: Passive Data Collection (COMPLETE)
- [x] In `recordIdentificationPerformance`, after calculating the `overallPerformanceScore`, record a `PerformanceDataPoint` for each DOM type.
- [x] Ensure data collection is passive and does not yet influence adaptation.

### Phase 3: Adaptation Jitter (COMPLETE, BUT NOW DEPRECATED)
- [x] In `applyModulation`, a small, random jitter (`domAdaptationJitterFactor`) was added to the final `normalizedPosition`.
- [x] **Status:** This approach has been deprecated in favor of the more deterministic "Forced Exploration" model in Phase 5.

### Phase 4: Initial Slope-Based Logic (COMPLETE, BUT NOW DEPRECATED)
- [x] Implemented `calculateDOMSpecificAdaptationSignal` using a recency-weighted linear regression slope.
- [x] **Status:** This initial implementation is functional but has been superseded by the superior PD Controller design in Phase 5.

---

### **Phase 5: Refactor to Localized PD Controller with Forced Exploration (NEXT TASK)**

**Objective:** Rearchitect the DOM profiling logic to use a robust, independent Proportional-Derivative (PD) controller for each DOM. This model will target a specific performance level, use performance trend slope to modulate adaptation, and introduce a deterministic exploration mechanism to ensure continued learning without the randomness of jitter.

#### **5.1: Configuration Changes (`GameConfiguration.swift`)**

1.  **Introduce Core PD Controller Parameters:**
    *   `public var domProfilingPerformanceTarget: CGFloat = 0.8`
    *   `public var domSlopeDampeningFactor: CGFloat = 10.0` (Replaces the "magic number" for the D-Term).
    *   `public var domMinDataPointsForProfiling: Int = 15` (Increased from the previous implicit value for statistical stability).

2.  **Introduce Forced Exploration Parameters:**
    *   `public var domConvergenceThreshold: CGFloat = 0.01` (The signal magnitude below which a DOM is considered stable).
    *   `public var domConvergenceDuration: Int = 5` (The number of rounds the signal must be below threshold to confirm convergence).
    *   `public var domExplorationNudgeFactor: CGFloat = 0.03` (The controlled, non-random nudge applied to a converged DOM to re-trigger learning).

3.  **Re-purpose DOM Priorities as Adaptation Rates:**
    *   Rename `domPriorities_LowMidArousal` to `domAdaptationRates_LowMidArousal`.
    *   Rename `domPriorities_HighArousal` to `domAdaptationRates_HighArousal`.
    *   These now act as base adaptation rates, not budget shares.

4.  **Remove Jitter:**
    *   The `domAdaptationJitterFactor` is now obsolete and should be removed.

#### **5.2: Refactor Core Logic (`AdaptiveDifficultyManager.swift`)**

1.  **State Tracking for Forced Exploration:**
    *   Add a new state-tracking property: `private var domConvergenceCounters: [DOMTargetType: Int] = [:]`. This will track how many consecutive rounds each DOM has been considered "converged".

2.  **Create Helper for Localized Confidence:**
    *   Create a new private function: `private func calculateLocalConfidence(for profile: DOMPerformanceProfile) -> CGFloat`.
    *   This function will compute confidence based *only* on the data within the provided profile (e.g., variance of performance, number of data points). It must **not** use the global `performanceHistory`.

3.  **Rearchitect `modulateDOMsWithProfiling`:**
    *   This function will be the primary entry point and will bypass the old budget and hysteresis systems.
    *   It will implement the main PD Controller and Forced Exploration logic.

4.  **Implement the PD Controller & Forced Exploration Loop:**
    *   Inside `modulateDOMsWithProfiling`, iterate through each `DOMTargetType`. For each DOM:
        *   **Guard Clause:** Check if `profile.performanceByValue.count >= config.domMinDataPointsForProfiling`. If not, skip this DOM.

        *   **a. Calculate Localized, Arousal-Gated Adaptation Rate:**
            *   Calculate `current_adaptation_rate` by interpolating between the new `domAdaptationRates` based on arousal.
            *   Calculate `local_confidence` using the new `calculateLocalConfidence` helper.
            *   `confidence_adjusted_rate = current_adaptation_rate * local_confidence`.

        *   **b. Calculate Performance Gap (The P-Term):**
            *   Calculate `average_performance` using the existing `calculateWeightedAveragePerformance` helper.
            *   `performance_gap = average_performance - config.domProfilingPerformanceTarget`.

        *   **c. Calculate Slope-Based Gain Modifier (The D-Term):**
            *   Calculate `slope` using the existing `calculateWeightedSlope` function.
            *   `gain_modifier = 1.0 / (1.0 + abs(slope) * config.domSlopeDampeningFactor)`.

        *   **d. Calculate Final Signal:**
            *   `final_signal = performance_gap * confidence_adjusted_rate * gain_modifier`.

        *   **e. Implement Forced Exploration Logic:**
            *   Check for convergence: `if abs(final_signal) < config.domConvergenceThreshold`.
                *   If true, increment the `domConvergenceCounters` for the current DOM.
            *   Else, reset the counter to `0`.
            *   Check for exploration trigger: `if (domConvergenceCounters[domType] ?? 0) >= config.domConvergenceDuration`.
                *   If true, apply a controlled `domExplorationNudgeFactor` to the DOM's `normalizedPosition`.
                *   Reset the convergence counter for that DOM to `0`.
                *   **Crucially, skip the regular modulation for this round** to let the nudge take effect cleanly.
            *   Else (not converged or not ready for a nudge), proceed with standard modulation.

        *   **f. Apply Modulation:**
            *   Call the existing `applyModulation` function, passing it the `final_signal`.

5.  **Update `applyModulation`:**
    *   **Remove the jitter logic.** The function should now only handle smoothing and clamping.

#### **5.3: Update Unit Tests (`ADMDOMSignalCalculationTests.swift`)**

1.  **Disable Old Tests:** Rename all existing tests to `test_DEPRECATED_*`.
2.  **Write New, Focused Tests:**
    *   Test `calculateLocalConfidence` to ensure it's independent of global state.
    *   Test the PD controller's P-Term and D-Term calculations in isolation.
    *   Test the "Forced Exploration" logic:
        *   Verify that a DOM with a consistently low signal has its convergence counter incremented.
        *   Verify that a converged DOM receives a nudge.
        *   Verify that a nudged DOM does not also receive a standard adaptation signal in the same round.
    *   Test that the `domMinDataPointsForProfiling` guard clause works correctly.

---

### Phase 6: Activation and Monitoring (FUTURE)

Once Phase 5 is complete and tested:
- [ ] Set `enableDomSpecificProfiling = true` in production configuration.
- [ ] Monitor telemetry for adaptation stability and player experience.
- [ ] Consider adding UI elements to show DOM-specific adaptation in debug mode.
