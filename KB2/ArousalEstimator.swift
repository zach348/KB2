import Foundation
import CoreGraphics

/// Responsible for estimating user's arousal level based on various inputs
class ArousalEstimator {
    
    // MARK: - Properties
    
    /// The estimated arousal level of the user (0-1 scale)
    private var _currentUserArousalLevel: CGFloat = 0.5
    
    /// Public accessor for the current user arousal level
    var currentUserArousalLevel: CGFloat {
        get { 
            return _currentUserArousalLevel 
        }
        set { 
            _currentUserArousalLevel = min(1.0, max(0.0, newValue)) 
        }
    }
    
    // MARK: - Initialization
    
    /// Initialize with an optional initial arousal value from self-report
    init(initialArousal: CGFloat? = nil) {
        if let initialValue = initialArousal {
            _currentUserArousalLevel = min(1.0, max(0.0, initialValue))
            logArousalChange(from: 0.5, to: _currentUserArousalLevel, source: "initial-self-report")
        }
    }
    
    // MARK: - Public Methods
    
    /// Update the user arousal estimate based on a direct self-report
    func updateFromSelfReport(reportedArousal: CGFloat) {
        let oldValue = _currentUserArousalLevel
        _currentUserArousalLevel = min(1.0, max(0.0, reportedArousal))
        logArousalChange(from: oldValue, to: _currentUserArousalLevel, source: "self-report")
    }
    
    // MARK: - Private Methods
    
    private func logArousalChange(from oldValue: CGFloat, to newValue: CGFloat, source: String) {
        print("USER AROUSAL changed from \(String(format: "%.2f", oldValue)) to \(String(format: "%.2f", newValue)) via \(source)")
    }
} 