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

### **Phase 5: Refactor to Localized PD Controller with Forced Exploration (PARTIALLY COMPLETE)**

**Status**: Core implementation complete but with critical issues identified. See `PD_CONTROLLER_ACTION_PLAN.md` for prioritized fixes.

**Objective:** Rearchitect the DOM profiling logic to use a robust, independent Proportional-Derivative (PD) controller for each DOM. This model will target a specific performance level, use performance trend slope to modulate adaptation, and introduce a deterministic exploration mechanism to ensure continued learning without the randomness of jitter.

#### **5.1: Configuration Changes (`GameConfiguration.swift`)** ✅ COMPLETE

1.  **Introduce Core PD Controller Parameters:** ✅
    *   `public var domProfilingPerformanceTarget: CGFloat = 0.8` ✅
    *   `public var domSlopeDampeningFactor: CGFloat = 10.0` ✅
    *   `public var domMinDataPointsForProfiling: Int = 15` ✅

2.  **Introduce Forced Exploration Parameters:** ✅
    *   `public var domConvergenceThreshold: CGFloat = 0.01` ✅
    *   `public var domConvergenceDuration: Int = 5` ✅
    *   `public var domExplorationNudgeFactor: CGFloat = 0.03` ✅

3.  **Re-purpose DOM Priorities as Adaptation Rates:** ✅
    *   Renamed to `domAdaptationRates_LowMidArousal` ✅
    *   Renamed to `domAdaptationRates_HighArousal` ✅
    *   These now act as base adaptation rates ✅

4.  **Remove Jitter:** ✅
    *   The `domAdaptationJitterFactor` has been removed from config ✅

#### **5.2: Refactor Core Logic (`AdaptiveDifficultyManager.swift`)** ⚠️ PARTIALLY COMPLETE

1.  **State Tracking for Forced Exploration:** ✅
    *   Added `private var domConvergenceCounters: [DOMTargetType: Int] = [:]` ✅

2.  **Create Helper for Localized Confidence:** ❌ MISSING
    *   `calculateLocalConfidence()` function not implemented
    *   Currently using global confidence instead (architectural violation)
    *   **CRITICAL**: See P1 Issue #4 in `PD_CONTROLLER_ACTION_PLAN.md`

3.  **Rearchitect `modulateDOMsWithProfiling`:** ✅ IMPLEMENTED WITH ISSUES
    *   Function exists and implements PD controller logic
    *   Has critical issues identified in evaluation
    *   **CRITICAL**: See P0 and P1 issues in `PD_CONTROLLER_ACTION_PLAN.md`

4.  **Implement the PD Controller & Forced Exploration Loop:** ⚠️ PARTIAL
    *   Inside `modulateDOMsWithProfiling`, iterate through each `DOMTargetType`. For each DOM:
        *   **Guard Clause:** Check if `profile.performanceByValue.count >= config.domMinDataPointsForProfiling`. If not, skip this DOM.

        *   **a. Calculate Localized, Arousal-Gated Adaptation Rate:** ❌ INCORRECT
            *   ❌ Uses hard switch instead of interpolation (P0 Issue #3)
            *   ❌ Uses global confidence instead of local confidence (P1 Issue #4)
            *   `confidence_adjusted_rate = current_adaptation_rate * local_confidence`.

        *   **b. Calculate Performance Gap (The P-Term):** ✅
            *   Correctly calculates `average_performance` using `calculateWeightedAveragePerformance`
            *   `performance_gap = average_performance - config.domProfilingPerformanceTarget`

        *   **c. Calculate Slope-Based Gain Modifier (The D-Term):** ✅
            *   Correctly calculates `slope` using `calculateWeightedSlope`
            *   `gain_modifier = 1.0 / (1.0 + abs(slope) * config.domSlopeDampeningFactor)`

        *   **d. Calculate Final Signal:** ❌ MISSING CLAMPING
            *   `final_signal = performance_gap * confidence_adjusted_rate * gain_modifier`
            *   **CRITICAL**: No signal clamping implemented (P0 Issue #2)

        *   **e. Implement Forced Exploration Logic:** ⚠️ PARTIAL
            *   ✅ Convergence detection implemented
            *   ✅ Convergence counters increment/reset correctly
            *   ⚠️ Nudge logic is overly simplistic (P2 Issue #6)
            *   ✅ Skips regular modulation when nudging

        *   **f. Apply Modulation:** ✅
            *   Correctly calls `applyModulation` with the signal

5.  **Update `applyModulation`:** ❓ UNCLEAR
    *   Jitter removal status needs verification
    *   `bypassSmoothing` flag introduced without documentation (P1 Issue #5)

#### **5.3: Update Unit Tests (`ADMDOMSignalCalculationTests.swift`)** ⚠️ PARTIALLY COMPLETE

1.  **Disable Old Tests:** ✅ Renamed to `test_DEPRECATED_*`
2.  **Write New, Focused Tests:** ⚠️ PARTIAL
    *   ❌ Test `calculateLocalConfidence` (function doesn't exist yet)
    *   ⚠️ Test the PD controller's P-Term and D-Term calculations (some tests exist but incomplete)
    *   ⚠️ Test the "Forced Exploration" logic:
        *   ✅ Convergence counter increment tests exist
        *   ✅ Nudge application tests exist
        *   ✅ Test that nudged DOM skips standard modulation
    *   ✅ Test that the `domMinDataPointsForProfiling` guard clause works correctly
    *   **Note**: Many debug test files created during troubleshooting

---

### Phase 5.5: TDD-Driven Robustness Enhancements (NOT STARTED)

**Objective:** Address architectural gaps and improve test coverage through a rigorous, Test-Driven Development process. Each item will be addressed by first writing a failing test that codifies the undesirable behavior, and then implementing the minimal code required to make the test pass.

**Status**: These enhancements have been identified as critical but not yet implemented. See `PD_CONTROLLER_ACTION_PLAN.md` for prioritized implementation plan.

#### **5.5.1: Eliminate the "Adaptation Gap"** ❌ NOT IMPLEMENTED

*   **Problem:** A gap exists where the system can become inert. If the `warmup` phase ends before `domMinDataPointsForProfiling` is met, the system enters the `standard` phase but the PD controller remains inactive, causing adaptation to freeze.
*   **Status:** **CRITICAL P0 Issue #1** - System breaking issue
*   **TDD Plan:**
    1.  Write Failing Test (`testAdaptationGap_WhenPDControllerIsNotReady_SystemIsUnguided`)
    2.  Implement Fallback Logic in `modulateDOMTargets`
    3.  Confirm Pass

#### **5.5.2: Prevent Signal Instability** ❌ NOT IMPLEMENTED

*   **Problem:** The calculated `final_signal` is not clamped, which could lead to excessively large, single-round jumps in difficulty if the P-Term is large.
*   **Status:** **CRITICAL P0 Issue #2** - Can cause jarring difficulty spikes
*   **TDD Plan:**
    1.  Write Failing Test (`testSignalClamping`)
    2.  Add `domMaxSignalPerRound` parameter to `GameConfiguration`
    3.  Implement clamping in `modulateDOMsWithProfiling`

#### **5.5.3: Improve Forced Exploration Nudge Logic** ⚠️ SIMPLISTIC IMPLEMENTATION

*   **Problem:** The current nudge logic is simplistic and may not effectively explore the boundaries of the parameter space.
*   **Status:** **P2 Issue #6** - Current implementation exists but needs refinement
*   **TDD Plan:**
    1.  Write Failing Tests (`testNudgeAtBoundaries`)
    2.  Refine Nudge Algorithm for boundary awareness
    3.  Confirm Pass

#### **5.5.4: Document Key Concepts** ❌ NOT COMPLETE

*   **Problem:** The theoretical basis for certain "magic numbers" is not documented, making them difficult to tune.
*   **Status:** **P3 Issue** - Technical debt
*   **Action:** Add comprehensive documentation to `GameConfiguration.swift`

#### **5.5.5: Unify Arousal-Based Rate Calculation** ❌ NOT IMPLEMENTED

*   **Problem:** The PD controller uses a hard switch for selecting adaptation rates based on arousal, while other parts of the system use smoother interpolation.
*   **Status:** **CRITICAL P0 Issue #3** - Likely cause of test failures
*   **TDD Plan:**
    1.  Write Failing Test (`testArousalBasedAdaptationRateInterpolation`)
    2.  Create `getInterpolatedDOMAdaptationRates()` helper function
    3.  Refactor PD Controller to use interpolation
    4.  Confirm Pass

---

### Phase 6: Activation and Monitoring (FUTURE)

Once Phase 5.5 is complete and tested:
- [ ] Set `enableDomSpecificProfiling = true` in production configuration.
- [ ] Monitor telemetry for adaptation stability and player experience.
- [ ] Consider adding UI elements to show DOM-specific adaptation in debug mode.
