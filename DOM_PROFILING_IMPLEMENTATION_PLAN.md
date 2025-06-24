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

### Phase 3: Adaptation Jitter (COMPLETE)
- [x] In `applyModulation`, add a small, random jitter (`domAdaptationJitterFactor`) to the final `normalizedPosition` if `enableDomSpecificProfiling` is true.
- [x] This ensures sufficient variance in DOM values for the profiling to be effective.

### Phase 4: Initial Slope-Based Logic (COMPLETE)
- [x] Implemented `calculateDOMSpecificAdaptationSignal` using a recency-weighted linear regression slope.
- [x] Implemented `modulateDOMsWithProfiling` to use this signal.
- [x] Added comprehensive unit tests.
- [x] **Status:** This initial implementation is functional but has been superseded by the superior design in Phase 5.

---

### **Phase 5: Refactor to Hybrid PD Controller Model (NEXT TASK)**

**Objective:** Rearchitect the DOM profiling logic to use a more robust and predictable Proportional-Derivative (PD) controller for each DOM. This model will target a specific performance level while using the performance trend's slope to modulate the adaptation rate, ensuring both accuracy and stability.

#### **5.1: Configuration Changes (`GameConfiguration.swift`)**

1.  **Introduce Performance Target:**
    -   Add a new property: `public var domProfilingPerformanceTarget: CGFloat = 0.8`. This will be the explicit performance score the system tries to achieve for each DOM.

2.  **Re-purpose DOM Priorities as Adaptation Rates:**
    -   Rename `domPriorities_LowMidArousal` to `domAdaptationRates_LowMidArousal`.
    -   Rename `domPriorities_HighArousal` to `domAdaptationRates_HighArousal`.
    -   Review and potentially adjust the values to reflect their new role as "base adaptation rates" rather than "budget shares". A good starting point is to ensure they are scaled appropriately (e.g., values between 0.5 and 1.5).

#### **5.2: Refactor Core Logic (`AdaptiveDifficultyManager.swift`)**

1.  **Create Helper for Weighted Average Performance:**
    -   Create a new private function: `private func calculateWeightedAveragePerformance(for profile: DOMPerformanceProfile) -> CGFloat`.
    -   This function will take a DOM profile, calculate the recency weights for its data points (using the existing 24-hour half-life model), and return the weighted average of the `performance` values.

2.  **Rearchitect `modulateDOMsWithProfiling`:**
    -   This function will become the main entry point and contain the primary logic.
    -   It should **no longer call** `calculateDOMSpecificAdaptationSignal`.
    -   It should **bypass** the global `calculateAdaptationSignalWithHysteresis` function.

3.  **Implement the PD Controller Loop:**
    -   Inside `modulateDOMsWithProfiling`, iterate through each `DOMTargetType`. For each DOM:
        
        a. **Calculate Arousal-Gated Adaptation Rate:**
           -   Calculate the `current_adaptation_rate` by interpolating between the new `domAdaptationRates_LowMidArousal` and `domAdaptationRates_HighArousal` based on the current arousal level. Use the existing `lerp` and `smoothstep` functions.
        
        b. **Apply Confidence Scaling:**
           -   Calculate the global `confidence` score using the existing `calculateAdaptationConfidence()` function.
           -   `confidence_adjusted_rate = current_adaptation_rate * confidence.total`.
        
        c. **Calculate Performance Gap (The P-Term):**
           -   Call your new `calculateWeightedAveragePerformance` helper to get the `average_performance` for the current DOM.
           -   `performance_gap = average_performance - config.domProfilingPerformanceTarget`.
        
        d. **Calculate Slope-Based Gain Modifier (The D-Term):**
           -   Calculate the `slope` of the performance trend using the existing `calculateWeightedSlope` function.
           -   `gain_modifier = 1.0 / (1.0 + abs(slope) * 10.0)`. (Note: Multiplying the slope by a factor, e.g., 10.0, will make the system more sensitive to changes in the slope).
        
        e. **Calculate Final Signal:**
           -   `final_signal = performance_gap * confidence_adjusted_rate * gain_modifier`.
        
        f. **Apply Modulation:**
           -   Call the existing `applyModulation` function, passing it the `final_signal` (potentially scaled by a small, constant factor to keep changes conservative). The `applyModulation` function already contains the necessary smoothing and jitter logic.

4.  **Retain Existing Infrastructure:**
    -   The `applyModulation` function remains unchanged and continues to handle:
        -   Direction-specific smoothing factors
        -   Final position clamping
        -   Jitter application (when DOM profiling is enabled)
    -   The arousal-gating system continues to function as before, converting normalized positions to absolute DOM values.

#### **5.3: Update Unit Tests (`ADMDOMSignalCalculationTests.swift`)**

1.  **Disable Old Tests:** 
    -   Rename the existing test functions for the slope-based signal (e.g., `testPositiveTrendAdaptationSignal`) to `test_DEPRECATED_PositiveTrendAdaptationSignal` to disable them without deleting them.

2.  **Write New Tests for the PD Controller:**
    -   Test that a performance score *above* the `0.8` target produces a positive adaptation signal (which increases difficulty for most DOMs).
    -   Test that a performance score *below* the target produces a negative adaptation signal (which decreases difficulty).
    -   Test that a steep slope correctly dampens the adaptation magnitude compared to a shallow slope.
    -   Test that the arousal-gated adaptation rates are working correctly (e.g., at high arousal, `discriminatoryLoad` adapts more aggressively than `targetCount`).
    -   Test edge cases: insufficient data, all performance scores equal to target, extreme slopes.

#### **5.4: Integration Notes**

**Key Architectural Decisions:**

1. **Decoupling:** Each DOM operates independently with its own PD controller. There is no shared "budget" or competition between DOMs.

2. **Obsolete Components:** When `enableDomSpecificProfiling` is true:
   - The old `distributeAdaptationBudget` function is bypassed.
   - The global hysteresis logic (`calculateAdaptationSignalWithHysteresis`) is bypassed.
   - The concept of a single `adaptationSignal` for all DOMs is replaced by individual signals.

3. **Retained Components:**
   - Global confidence calculation still scales all adaptation rates.
   - Smoothing factors continue to ensure gradual changes.
   - Jitter continues to provide exploration.
   - Arousal-gating continues to define the valid range for each DOM.

**Expected Behavior:**

- The system will continuously adjust each DOM to maintain player performance at approximately 80%.
- DOMs with high arousal-specific adaptation rates will respond more aggressively to performance deviations.
- When the player is very sensitive to a DOM (steep slope), the system will make smaller, more cautious adjustments.
- The system will naturally find the "edge" of player capability for constraint-based DOMs like `responseTime`.

---

### Phase 6: Activation and Monitoring (FUTURE)

Once Phase 5 is complete and tested:
- [ ] Set `enableDomSpecificProfiling = true` in production configuration.
- [ ] Monitor telemetry for adaptation stability and player experience.
- [ ] Consider adding UI elements to show DOM-specific adaptation in debug mode.
