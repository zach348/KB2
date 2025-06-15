# Breathing Guidance Refactoring Plan

## Date: June 15, 2025

### Overview
This document outlines the refactoring needed to clean up legacy breathing guidance variables and standardize naming conventions across the codebase.

### Issues Identified

#### 1. Duplicate Variables in GameConfiguration.swift
**Current State:**
```swift
// Dynamic breathing min/max durations
let dynamicBreathingMinInhaleDuration: TimeInterval = 3.5
let dynamicBreathingMaxInhaleDuration: TimeInterval = 4.25
let dynamicBreathingMinExhaleDuration: TimeInterval = 4.25
let dynamicBreathingMaxExhaleDuration: TimeInterval = 8.0

// Duplicate variables (marked as "RETAINED FOR NOW, POTENTIALLY FOR HOLDS")
let breathingInhaleDuration_Min: TimeInterval = 3.5  // Duplicate
let breathingInhaleDuration_Max: TimeInterval = 4.25  // Duplicate
let breathingExhaleDuration_Min: TimeInterval = 4.25  // Duplicate
let breathingExhaleDuration_Max: TimeInterval = 8.0   // Duplicate
````

__Action:__ Remove the duplicate variables as they're not being used.

#### 2. Inconsistent Naming Conventions

__Current State:__

- Mixed use of `breathing*` and `dynamicBreathing*` prefixes
- Hold proportions use underscores: `holdAfterInhaleProportion_LowArousal`
- Other variables use camelCase: `breathingHapticMinDelay`

__Action:__ Standardize to camelCase throughout:

- `holdAfterInhaleProportion_LowArousal` → `holdAfterInhaleProportionLowArousal`
- `holdAfterInhaleProportion_HighArousal` → `holdAfterInhaleProportionHighArousal`
- `holdAfterExhaleProportion_LowArousal` → `holdAfterExhaleProportionLowArousal`
- `holdAfterExhaleProportion_HighArousal` → `holdAfterExhaleProportionHighArousal`

#### 3. Incorrect Value

__Current State:__

```swift
let preHoldExhaleProportion: TimeInterval = 0.0075 // Comment says "5% of exhale"
```

__Action:__ Change to 0.05 to match the comment and intended behavior.

#### 4. Unused Variable

__Current State:__

```swift
let breathingHapticAccelFactor: Double = 0.13  // Not used in current implementation
```

__Action:__ Remove this unused variable.

#### 5. Legacy Code in ArousalManager.swift

__Current State:__

- Contains breathing duration variables that duplicate GameScene functionality
- Has `updateDynamicBreathingParameters()` method that appears unused

__Action:__ Remove all breathing-related code from ArousalManager.swift

#### 6. Legacy Code in VHAManager.swift

__Current State:__

- Contains breathing haptic functionality that duplicates GameScene
- Has its own breathing duration variables

__Action:__ Remove all breathing-related code from VHAManager.swift

### Test Coverage Review

Current tests appear comprehensive, covering:

- State transitions to/from breathing
- Dynamic breathing parameter updates
- Visual fade behavior
- Breathing animation parameters
- Session breathing transition points

### Implementation Order

1. Fix the `preHoldExhaleProportion` value (highest priority as it affects behavior)
2. Remove duplicate variables in GameConfiguration
3. Standardize naming conventions for hold proportions
4. Remove unused `breathingHapticAccelFactor`
5. Remove legacy code from ArousalManager
6. Remove legacy code from VHAManager
7. Run all tests to ensure no breaking changes
8. Update any affected tests

### Risk Assessment

- __Low Risk:__ Removing duplicate/unused variables
- __Medium Risk:__ Renaming variables (need to ensure all references are updated)
- __Medium Risk:__ Removing legacy code (need to verify it's truly unused)
