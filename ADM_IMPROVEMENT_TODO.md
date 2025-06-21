# Adaptive Difficulty Manager (ADM) Improvement Plan

## Overview
This document outlines incremental improvements to address two critical issues in the current ADM:
1. **Lack of Performance History**: Single-sample decision making leads to high variance
2. **No Hysteresis**: Risk of oscillation around performance thresholds
3. **Hard Threshold Switches**: Discontinuity at arousal 0.7 for KPI weights and DOM hierarchy

## Target Improvements
- Smooth interpolation between arousal-based configurations (20% transition zone, smooth step curve)
- Performance history tracking with trend analysis
- Hysteresis mechanisms to prevent oscillation
- Confidence-based adaptation scaling

---

## Phase 1: Foundation - Performance History Tracking

### Step 1.1: Create Performance History Structure
- [x] **Create `PerformanceHistoryEntry` struct**
- [x] **Add history storage to ADM**
- [x] **Add configuration parameters to GameConfiguration**

### Step 1.2: Update recordIdentificationPerformance
- [x] **Store performance entries in history**
- [x] **Maintain rolling window** (remove oldest when exceeding maxHistorySize)
- [x] **Keep existing single-sample logic initially** (no breaking changes)
- [x] **Add DataLogger events for history tracking**

### Step 1.3: Add History Analytics Functions
- [x] **Implement `getPerformanceMetrics()`**
  ```swift
  private func getPerformanceMetrics() -> (average: CGFloat, trend: CGFloat, variance: CGFloat) {
      // Calculate rolling average of performance scores
      // Calculate trend using linear regression slope
      // Calculate variance for consistency measurement
  }
  ```

- [x] **Add helper functions**
  ```swift
  private func calculateLinearTrend() -> CGFloat
  private func calculatePerformanceVariance() -> CGFloat
  private func getRecentPerformanceWindow() -> [PerformanceHistoryEntry]
  ```

### Validation Checkpoint 1
- [x] **Unit tests for history management**
- [x] **Verify history storage without behavior changes**
- [x] **DataLogger integration for history metrics**
- [x] **Test edge cases** (empty history, single entry)

---

## Phase 1.5: KPI Weight Interpolation

### Step 1.5.1: Add Interpolation Utilities
- [x] **Create interpolation helper functions**
  ```swift
  private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
      return a + (b - a) * t
  }
  
  private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
      let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
      return t * t * (3 - 2 * t)  // Cubic smoothing
  }
  ```

### Step 1.5.2: Add Transition Configuration
- [x] **Add to GameConfiguration**
  ```swift
  // KPI Weight Transition Configuration
  let kpiWeightTransitionStart: CGFloat = 0.6
  let kpiWeightTransitionEnd: CGFloat = 0.8
  let useKPIWeightInterpolation: Bool = true
  ```

### Step 1.5.3: Implement KPI Weight Interpolation
- [x] **Create `getInterpolatedKPIWeights()` function**
  ```swift
  private func getInterpolatedKPIWeights(arousal: CGFloat) -> KPIWeights {
      guard config.useKPIWeightInterpolation else {
          // Fallback to original behavior
          return arousal >= config.arousalThresholdForKPIAndHierarchySwitch ?
                 config.kpiWeights_HighArousal : config.kpiWeights_LowMidArousal
      }
      
      let start = config.kpiWeightTransitionStart
      let end = config.kpiWeightTransitionEnd
      
      if arousal <= start {
          return config.kpiWeights_LowMidArousal
      } else if arousal >= end {
          return config.kpiWeights_HighArousal
      } else {
          let t = smoothstep(start, end, arousal)
          return KPIWeights(
              taskSuccess: lerp(config.kpiWeights_LowMidArousal.taskSuccess, 
                              config.kpiWeights_HighArousal.taskSuccess, t),
              tfTtfRatio: lerp(config.kpiWeights_LowMidArousal.tfTtfRatio, 
                             config.kpiWeights_HighArousal.tfTtfRatio, t),
              reactionTime: lerp(config.kpiWeights_LowMidArousal.reactionTime, 
                               config.kpiWeights_HighArousal.reactionTime, t),
              responseDuration: lerp(config.kpiWeights_LowMidArousal.responseDuration, 
                                   config.kpiWeights_HighArousal.responseDuration, t),
              tapAccuracy: lerp(config.kpiWeights_LowMidArousal.tapAccuracy, 
                              config.kpiWeights_HighArousal.tapAccuracy, t)
          )
      }
  }
  ```

- [x] **Update `calculateOverallPerformanceScore()` to use interpolated weights**

### Validation Checkpoint 1.5
- [x] **Test smooth transitions around 0.6-0.8 arousal range**
- [x] **Verify no performance discontinuities**
- [x] **A/B test with interpolation on/off**

---

## Phase 2: Trend-Based Adaptation

### Step 2.1: Implement Weighted Performance Calculation
- [x] **Create `calculateAdaptivePerformanceScore()` function**
  ```swift
  func calculateAdaptivePerformanceScore(currentScore: CGFloat) -> CGFloat {
      guard config.usePerformanceHistory && performanceHistory.count >= config.minimumHistoryForTrend else {
          return currentScore
      }
      
      let (average, trend, _) = getPerformanceMetrics()
      
      // Weight recent performance more heavily
      let recentWeight = config.currentPerformanceWeight
      let historyWeight = config.historyInfluenceWeight
      let trendWeight = config.trendInfluenceWeight
      
      // Consider trend in final score
      let trendAdjustment = trend * trendWeight
      
      let weightedScore = (currentScore * recentWeight) +
                          (average * historyWeight) +
                          trendAdjustment
      
      return max(0.0, min(1.0, weightedScore)) // Clamp the final adaptive score
  }
  ```

### Step 2.2: Add Configuration Parameters
- [x] **Extend GameConfiguration**
  ```swift
  // Trend-Based Adaptation Configuration
  let currentPerformanceWeight: CGFloat = 0.7
  let historyInfluenceWeight: CGFloat = 0.3
  let trendInfluenceWeight: CGFloat = 0.1
  let usePerformanceHistory: Bool = true
  let minimumHistoryForTrend: Int = 3
  ```

### Step 2.3: Update Performance Score Calculation
- [x] **Modify `modulateDOMTargets()` to use adaptive score**
- [x] **Add feature flag for gradual migration**
- [x] **Add DataLogger events for trend metrics**

### Validation Checkpoint 2
- [x] **Test trend detection accuracy**
- [x] **Verify smoother difficulty transitions**
- [x] **Monitor for overcompensation issues**
- [x] **Test with synthetic performance patterns**

---

## Phase 2.5: DOM Priority Weight Interpolation

### Step 2.5.1: Create DOM Priority System
- [x] **Define DOM priority weights for each arousal state**
  ```swift
  // Add to GameConfiguration
  let domPriorities_LowMidArousal: [DOMTargetType: CGFloat] = [
      .targetCount: 5.0,
      .responseTime: 4.0,
      .discriminatoryLoad: 3.0,
      .meanBallSpeed: 2.0,
      .ballSpeedSD: 1.0
  ]
  
  let domPriorities_HighArousal: [DOMTargetType: CGFloat] = [
      .discriminatoryLoad: 5.0,
      .meanBallSpeed: 4.0,
      .ballSpeedSD: 3.0,
      .responseTime: 2.0,
      .targetCount: 1.0
  ]
  ```

### Step 2.5.2: Implement Priority Interpolation
- [x] **Create `calculateInterpolatedDOMPriority()` function**
  ```swift
  private func calculateInterpolatedDOMPriority(domType: DOMTargetType, arousal: CGFloat) -> CGFloat {
      let lowPriority = config.domPriorities_LowMidArousal[domType] ?? 1.0
      let highPriority = config.domPriorities_HighArousal[domType] ?? 1.0
      let t = smoothstep(config.kpiWeightTransitionStart, config.kpiWeightTransitionEnd, arousal)
      return lerp(lowPriority, highPriority, t)
  }
  ```

### Step 2.5.3: Update DOM Modulation with Weighted Budget
- [x] **Replace hierarchical approach with weighted distribution**
  ```swift
  private func distributeAdaptationBudget(totalBudget: CGFloat, arousal: CGFloat) -> [DOMTargetType: CGFloat] {
      let priorities = DOMTargetType.allCases.map { 
          (dom: $0, priority: calculateInterpolatedDOMPriority(domType: $0, arousal: arousal))
      }
      
      let totalPriority = priorities.reduce(0) { $0 + $1.priority }
      
      return Dictionary(uniqueKeysWithValues: priorities.map { 
          ($0.dom, ($0.priority / totalPriority) * totalBudget)
      })
  }
  ```

### Validation Checkpoint 2.5
- [x] **Test DOM adjustment balance across arousal range**
- [x] **Verify smooth priority transitions**
- [x] **Compare against original hierarchical approach**

---

## Phase 3: Basic Hysteresis Implementation

### Step 3.1: Add Hysteresis Configuration
- [x] **Define threshold structure**
  ```swift
  struct AdaptationThresholds {
      let performanceTarget: CGFloat = 0.5
      let increaseThreshold: CGFloat = 0.55    // Must exceed to increase difficulty
      let decreaseThreshold: CGFloat = 0.45    // Must fall below to decrease
      let baseDeadZone: CGFloat = 0.02
      let hysteresisEnabled: Bool = true
  }
  ```

- [x] **Add to GameConfiguration**
  ```swift
  // Hysteresis Configuration
  let adaptationIncreaseThreshold: CGFloat = 0.55
  let adaptationDecreaseThreshold: CGFloat = 0.45
  let enableHysteresis: Bool = true
  let minStableRoundsBeforeDirectionChange: Int = 2
  ```

### Step 3.2: Add Direction Memory
- [x] **Create adaptation direction tracking**
  ```swift
  private enum AdaptationDirection {
      case increasing, decreasing, stable
  }
  
  private var lastAdaptationDirection: AdaptationDirection = .stable
  private var directionChangeCount: Int = 0
  private var lastSignificantChange: TimeInterval = 0
  ```

### Step 3.3: Update Adaptation Signal Calculation
- [x] **Implement hysteresis logic in `modulateDOMTargets()`**
  ```swift
  private func calculateAdaptationSignalWithHysteresis(performanceScore: CGFloat) -> CGFloat {
      guard config.enableHysteresis else {
          return (performanceScore - 0.5) * 2.0  // Original logic
      }
      
      let thresholds = AdaptationThresholds()
      
      if performanceScore > thresholds.increaseThreshold {
          if lastAdaptationDirection == .decreasing && 
             directionChangeCount < config.minStableRoundsBeforeDirectionChange {
              return 0.0  // Prevent immediate reversal
          }
          return (performanceScore - thresholds.performanceTarget) * 2.0
      } else if performanceScore < thresholds.decreaseThreshold {
          if lastAdaptationDirection == .increasing && 
             directionChangeCount < config.minStableRoundsBeforeDirectionChange {
              return 0.0  // Prevent immediate reversal
          }
          return (performanceScore - thresholds.performanceTarget) * 2.0
      } else {
          return 0.0  // In neutral zone
      }
  }
  ```

### Validation Checkpoint 3
- [x] **Test oscillation prevention**
- [x] **Verify responsiveness to genuine performance changes**
- [x] **Monitor direction change frequency**
- [x] **Test edge cases** (rapid performance swings)

---

## Phase 4: Advanced Confidence-Based Adaptation

### Step 4.1: Implement Confidence Calculation
- [ ] **Create comprehensive confidence metrics**
  ```swift
  private func calculateAdaptationConfidence() -> CGFloat {
      guard !performanceHistory.isEmpty else { return 0.5 }
      
      let (_, _, variance) = getPerformanceMetrics()
      
      // High variance = low confidence (0-1 scale)
      let varianceConfidence = max(0, 1.0 - min(variance / 0.5, 1.0))
      
      // Consistent direction = high confidence
      let directionConfidence = min(CGFloat(directionChangeCount) / 5.0, 1.0)
      
      // History size confidence (more data = more confident)
      let historyConfidence = min(CGFloat(performanceHistory.count) / CGFloat(config.performanceHistoryWindowSize), 1.0)
      
      return (varianceConfidence + directionConfidence + historyConfidence) / 3.0
  }
  ```

### Step 4.2: Scale Adaptation by Confidence
- [ ] **Update adaptation signal scaling**
  ```swift
  let confidence = calculateAdaptationConfidence()
  let confidenceMultiplier = config.minConfidenceMultiplier + 
                           (1.0 - config.minConfidenceMultiplier) * confidence
  remainingAdaptationSignalBudget *= confidenceMultiplier
  ```

### Step 4.3: Dynamic Threshold Adjustment
- [ ] **Implement confidence-based threshold widening**
  ```swift
  private func getEffectiveAdaptationThresholds() -> AdaptationThresholds {
      let confidence = calculateAdaptationConfidence()
      let uncertaintyMultiplier = 2.0 - confidence  // 1.0 to 2.0 range
      
      return AdaptationThresholds(
          increaseThreshold: 0.5 + (0.05 * uncertaintyMultiplier),
          decreaseThreshold: 0.5 - (0.05 * uncertaintyMultiplier),
          baseDeadZone: config.adaptationSignalDeadZone * uncertaintyMultiplier
      )
  }
  ```

### Step 4.4: Add Configuration
- [ ] **Extend GameConfiguration**
  ```swift
  // Confidence-Based Adaptation
  let enableConfidenceScaling: Bool = true
  let minConfidenceMultiplier: CGFloat = 0.2  // Minimum adaptation strength
  let confidenceThresholdWidening: CGFloat = 0.05
  ```

### Validation Checkpoint 4
- [ ] **Test adaptation with varying performance consistency**
- [ ] **Verify confidence calculations are meaningful**
- [ ] **Test with synthetic erratic vs. consistent performance**
- [ ] **Monitor adaptation responsiveness across confidence levels**

---

## Phase 4.5: Cross-Session Persistence

### Step 4.5.1: Enhance Data Models & Persistence Layer
- [ ] **Make `PerformanceHistoryEntry` and related enums `Codable`**
- [ ] **Create `PersistedADMState` struct for session data**
  ```swift
  struct PersistedADMState: Codable {
      let performanceHistory: [PerformanceHistoryEntry]
      let lastAdaptationDirection: AdaptationDirection
      let directionStableCount: Int
      let normalizedPositions: [DOMTargetType: CGFloat]
  }
  ```
- [ ] **Implement `ADMPersistenceManager` for session data**
  - `saveState(state: PersistedADMState, for userId: String)`
  - `loadState(for userId: String) -> PersistedADMState?`
  - `clearState(for userId: String)`
- [ ] **Ensure `UserIDManager` persists `userId` independently**

### Step 4.5.2: Integrate with ADM
- [ ] **Add `clearPastSessionData` flag to `GameConfiguration`**
- [ ] **Update `AdaptiveDifficultyManager.init`**:
  - Get `userId` from `UserIDManager`.
  - If `clearPastSessionData` is true, call `ADMPersistenceManager.clearState(for: userId)`.
  - Otherwise, load persisted state.
- [ ] **Implement `saveState()` and `loadState()` in ADM, using the `userId`**
- [ ] **Call `saveState()` on app background/termination via `AppDelegate`**

### Step 4.5.3: Update Confidence Calculation
- [ ] **Modify `calculateAdaptationConfidence` to use combined history (current + persisted)**
- [ ] **Implement recency weighting for older session data**

### Validation Checkpoint 4.5
- [ ] **Unit tests for `ADMPersistenceManager` (save, load, clear per user)**
- [ ] **Verify `UserIDManager` is unaffected by `clearPastSessionData`**
- [ ] **Integration tests for loading/saving state in ADM**
- [ ] **Test adaptation behavior with and without persisted data**

---

## Phase 5: Polish and Advanced Features

### Step 5.1: Predictive Elements
- [ ] **Implement fatigue detection**
  ```swift
  private func detectFatiguePattern() -> Bool {
      // Declining trend + increasing variance over time
      let (_, trend, variance) = getPerformanceMetrics()
      let sessionProgress = calculateSessionProgress()
      
      return trend < -0.1 && variance > 0.3 && sessionProgress > 0.5
  }
  ```

- [ ] **Add warm-up detection**
  ```swift
  private func isInWarmupPhase() -> Bool {
      return performanceHistory.count < config.warmupPhaseLength
  }
  ```

- [ ] **Implement session-aware adaptation**
  ```swift
  private func getSessionAwareAdaptationRate() -> CGFloat {
      let progress = calculateSessionProgress()
      
      if isInWarmupPhase() {
          return config.warmupAdaptationRate  // Slower adaptation
      } else if detectFatiguePattern() {
          return config.fatigueAdaptationRate  // Faster difficulty reduction
      } else {
          return 1.0  // Normal adaptation rate
      }
  }
  ```

### Step 5.2: DOM-Specific Performance Profiling
- [ ] **Create DOM performance tracking**
  ```swift
  struct DOMPerformanceProfile {
      let domType: DOMTargetType
      var performanceByValue: [(value: CGFloat, performance: CGFloat)] = []
      var optimalRange: (min: CGFloat, max: CGFloat)?
      
      mutating func recordPerformance(domValue: CGFloat, performance: CGFloat) {
          performanceByValue.append((domValue, performance))
          // Keep only recent samples
          if performanceByValue.count > 20 {
              performanceByValue.removeFirst()
          }
          updateOptimalRange()
      }
  }
  ```

### Step 5.3: Enhanced Configuration and Presets
- [ ] **Add player profile presets**
  ```swift
  enum PlayerProfile {
      case novice, intermediate, expert, adaptive
      
      var adaptationConfiguration: AdaptationConfiguration {
          switch self {
          case .novice:
              return AdaptationConfiguration(
                  adaptationRate: 0.8,
                  confidenceThreshold: 0.3,
                  historyWeight: 0.4
              )
          // ... other profiles
          }
      }
  }
  ```

- [ ] **Runtime configuration adjustment**
  ```swift
  // Add to ADM
  func updateConfiguration(_ newConfig: AdaptationConfiguration) {
      // Allow runtime tuning for testing
  }
  ```

### Step 5.4: Advanced Analytics and Logging
- [ ] **Enhanced DataLogger integration**
  ```swift
  // Log comprehensive adaptation events
  DataLogger.shared.logAdaptationDecision(
      performanceScore: score,
      confidence: confidence,
      adaptationSignal: signal,
      domAdjustments: adjustments,
      historicalContext: getHistorySnapshot()
  )
  ```

- [ ] **Performance visualization helpers**
  ```swift
  func generateAdaptationReport() -> AdaptationReport {
      // Generate summary of adaptation behavior for analysis
  }
  ```

### Validation Checkpoint 5
- [ ] **Comprehensive integration testing**
- [ ] **Performance impact assessment**
- [ ] **User experience validation**
- [ ] **Data analytics verification**

---

## Testing Strategy

### Unit Tests
- [ ] **Interpolation function accuracy**
- [ ] **History management edge cases**
- [ ] **Hysteresis threshold behavior**
- [ ] **Confidence calculation validation**

### Integration Tests
- [ ] **Full adaptation cycle testing**
- [ ] **Arousal transition scenarios**
- [ ] **Performance pattern simulation**
- [ ] **GameScene integration verification**

### A/B Testing Framework
- [ ] **Feature flag infrastructure**
- [ ] **Metrics collection for comparison**
- [ ] **Statistical significance testing**
- [ ] **Performance impact monitoring**

### Real-World Validation
- [ ] **Session recordings analysis**
- [ ] **Player feedback collection**
- [ ] **Adaptation behavior visualization**
- [ ] **Long-term stability testing**

---

## Priority Order for Implementation

1. **Phase 1 + 1.5**: Foundation + KPI interpolation (High impact, low risk)
2. **Phase 2**: History-based adaptation (Medium impact, medium risk)
3. **Phase 3**: Basic hysteresis (High impact, low-medium risk)
4. **Phase 2.5**: DOM priority interpolation (Medium impact, medium risk)
5. **Phase 4**: Confidence-based scaling (Medium-high impact, medium risk)
6. **Phase 5**: Advanced features (Low-medium impact, low risk)

## Success Metrics

- [ ] **Reduced adaptation oscillation frequency**
- [ ] **Smoother difficulty transitions**
- [ ] **Improved player engagement metrics**
- [ ] **More stable challenge levels**
- [ ] **Better adaptation to individual player patterns**

---

## Notes

- Each phase should be thoroughly tested before moving to the next
- Feature flags should be used to enable gradual rollout
- DataLogger integration is critical for measuring improvement
- Consider player feedback during testing phases
- Performance impact should be monitored throughout implementation
