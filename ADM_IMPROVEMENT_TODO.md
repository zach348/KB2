# ADM Improvement TODO List

High-level tracking of major initiatives for the Adaptive Difficulty Manager.

---

### Completed
- [x] **Phase 1: Foundational Data Structures** - `DOMPerformanceProfile` and related configuration integrated.
- [x] **Phase 2: Passive Data Collection** - ADM now correctly collects performance data for each DOM parameter in the background.
- [x] **Phase 3: Adaptation Jitter** - A "jitter" mechanism is implemented to ensure sufficient variance in DOM values for analysis.
- [x] **Phase 3.5: Persistence** - `domPerformanceProfiles` are successfully persisted and loaded across sessions.
- [x] **Phase 4: Initial DOM Profiling Logic** - A first-pass implementation of profile-based adaptation using a slope-based "hill-climbing" approach has been implemented and tested.

---

### Next Up

- [ ] **Phase 5: Refactor DOM Profiling to Hybrid PD Controller Model**
  - **Objective:** Rearchitect the DOM-specific adaptation logic from the simple slope-based model to a more robust Proportional-Derivative (PD) controller.
  - **Reason:** The current "hill-climbing" model has a critical flaw where it can fail to challenge skilled players on constraint-based DOMs (e.g., `responseTime`). The new model will target a specific performance level (the P-term) while using the performance slope to modulate the adaptation rate (the D-term), creating a more stable and effective system.
  - **See:** `DOM_PROFILING_IMPLEMENTATION_PLAN.md` for detailed technical specifications.

---

### Future Ideas

- [ ] **Contextual DOM Profiles** - Consider maintaining separate performance profiles for different arousal ranges, as player capability may vary significantly.
- [ ] **Cross-DOM Correlation Analysis** - Analyze relationships between DOM performance (e.g., does increasing ball speed always impact reaction time performance?).
- [ ] **Player Skill Trajectory Modeling** - Use long-term data to model and predict player improvement curves.
- [ ] **Adaptive Performance Target** - Instead of a fixed 0.8 target, dynamically adjust based on session goals or player preferences.
