import UIKit

enum TimeGranularity: Int, CaseIterable {
    case daily = 0
    case weekly = 1
    case monthly = 2
    
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

struct SessionData {
    let date: Date
    let preStress: Double?
    let postStress: Double?
    let preCalm: Double?
    let postCalm: Double?
    let focusQuality: Double?
}

class ProgressViewController: UIViewController {
    
    // MARK: - Properties
    
    // Brand Colors
    private let primaryColor = UIColor(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0, alpha: 1.0) // #77FDC7
    private let secondaryColor = UIColor(red: 0xA0/255.0, green: 0x9E/255.0, blue: 0xA1/255.0, alpha: 1.0) // #A09EA1
    private let darkColor = UIColor(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0, alpha: 1.0) // #242424
    private let whiteColor = UIColor.white // #FFFFFF
    
    // UI Elements
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let mainStackView = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let timeGranularityControl = UISegmentedControl(items: TimeGranularity.allCases.map { $0.displayName })
    private let stressChartView = LineChartView()
    private let calmChartView = LineChartView()
    private let focusQualityChartView = LineChartView()
    private let noDataLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    
    // Data
    private var rawHistoricalData: [HistoricalSessionData] = []
    private var sessionData: [SessionData] = []
    private var currentGranularity: TimeGranularity = .daily
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        print("PROGRESS_VIEW: viewDidLoad called")
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("PROGRESS_VIEW: viewWillAppear called - loading fresh data")
        loadProgressData()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = darkColor
        
        // Setup scroll view
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        setupContent()
        setupConstraints()
    }
    
    private func setupContent() {
        // Main stack view for responsive layout
        mainStackView.axis = .vertical
        mainStackView.spacing = 32
        mainStackView.alignment = .fill
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStackView)
        
        // Title
        titleLabel.text = "Your Progress"
        titleLabel.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = whiteColor
        titleLabel.textAlignment = .center
        
        // Subtitle
        subtitleLabel.text = "Track your improvement over time"
        subtitleLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        subtitleLabel.textColor = secondaryColor
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        
        // Time granularity control
        timeGranularityControl.selectedSegmentIndex = currentGranularity.rawValue
        timeGranularityControl.backgroundColor = UIColor(white: 0.2, alpha: 0.5)
        timeGranularityControl.selectedSegmentTintColor = primaryColor
        timeGranularityControl.setTitleTextAttributes([.foregroundColor: darkColor], for: .selected)
        timeGranularityControl.setTitleTextAttributes([.foregroundColor: secondaryColor], for: .normal)
        timeGranularityControl.addTarget(self, action: #selector(timeGranularityChanged), for: .valueChanged)
        
        // Chart setup
        setupChartView(stressChartView, title: "Stress Level", metric: "Lower is better")
        setupChartView(calmChartView, title: "Calm ↔ Jittery", metric: "Lower is better")
        setupChartView(focusQualityChartView, title: "Focus Quality", metric: "Higher is better")
        
        // No data label (initially hidden)
        noDataLabel.text = "Complete a few sessions to see your progress trends.\n\nYour pre and post-session assessments will be tracked here to show your improvement over time."
        noDataLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        noDataLabel.textColor = secondaryColor
        noDataLabel.textAlignment = .center
        noDataLabel.numberOfLines = 0
        noDataLabel.isHidden = true
        
        // Done button
        setupButton(doneButton, title: "Done", isPrimary: true)
        doneButton.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
        
        // Add elements to stack view
        mainStackView.addArrangedSubview(titleLabel)
        mainStackView.addArrangedSubview(subtitleLabel)
        
        // Add spacing
        let spacer1 = UIView()
        spacer1.heightAnchor.constraint(equalToConstant: 16).isActive = true
        mainStackView.addArrangedSubview(spacer1)
        
        mainStackView.addArrangedSubview(timeGranularityControl)
        
        // Add spacing after granularity control
        let spacer1b = UIView()
        spacer1b.heightAnchor.constraint(equalToConstant: 16).isActive = true
        mainStackView.addArrangedSubview(spacer1b)
        
        mainStackView.addArrangedSubview(stressChartView)
        mainStackView.addArrangedSubview(calmChartView)
        mainStackView.addArrangedSubview(focusQualityChartView)
        mainStackView.addArrangedSubview(noDataLabel)
        
        // Add spacing before done button
        let spacer2 = UIView()
        spacer2.heightAnchor.constraint(equalToConstant: 32).isActive = true
        mainStackView.addArrangedSubview(spacer2)
        
        mainStackView.addArrangedSubview(doneButton)
        
        // Loading indicator
        loadingIndicator.color = primaryColor
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupChartView(_ chartView: LineChartView, title: String, metric: String) {
        chartView.configure(
            title: title,
            metric: metric,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            darkColor: darkColor,
            whiteColor: whiteColor
        )
        chartView.heightAnchor.constraint(equalToConstant: 280).isActive = true
    }
    
    private func setupButton(_ button: UIButton, title: String, isPrimary: Bool) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.layer.cornerRadius = 12
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        if isPrimary {
            button.backgroundColor = primaryColor
            button.setTitleColor(darkColor, for: .normal)
            button.layer.borderWidth = 0
        } else {
            button.backgroundColor = .clear
            button.setTitleColor(secondaryColor, for: .normal)
            button.layer.borderWidth = 2
            button.layer.borderColor = secondaryColor.cgColor
        }
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Main stack view
            mainStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            mainStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            mainStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            mainStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
            
            // Loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    // MARK: - Data Loading
    private func loadProgressData() {
        print("PROGRESS_VIEW: loadProgressData called - starting data fetch")
        showLoading(true)
        
        // Get historical EMA data from DataLogger
        DataLogger.shared.getHistoricalEMAData { [weak self] historicalData in
            print("PROGRESS_VIEW: DataLogger completion handler called with \(historicalData.count) sessions")
            
            guard let self = self else { 
                print("PROGRESS_VIEW: ERROR - ProgressViewController was deallocated before data loading completed")
                return 
            }
            
            DispatchQueue.main.async {
                print("PROGRESS_VIEW: Processing data on main thread")
                self.showLoading(false)
                self.rawHistoricalData = historicalData
                self.processDataForCurrentGranularity()
                
                if historicalData.isEmpty {
                    print("PROGRESS_VIEW: No historical EMA data found")
                } else {
                    print("PROGRESS_VIEW: Loaded \(historicalData.count) historical sessions")
                    for (index, session) in historicalData.enumerated() {
                        print("PROGRESS_VIEW: Session \(index): Date: \(session.sessionDate)")
                        print("PROGRESS_VIEW: - Pre-session EMA: \(session.preSessionEMA)")
                        print("PROGRESS_VIEW: - Post-session EMA: \(session.postSessionEMA)")
                    }
                }
            }
        }
    }
    
    private func processDataForCurrentGranularity() {
        let rawSessionData = convertHistoricalDataToSessionData(rawHistoricalData)
        self.sessionData = groupAndAverageData(rawSessionData, by: currentGranularity)
        self.updateUI()
    }
    
    private func convertHistoricalDataToSessionData(_ historicalData: [HistoricalSessionData]) -> [SessionData] {
        return historicalData.compactMap { session in
            // Extract EMA values from the stored responses using the correct keys
            let preStress = extractEMAValue(from: session.preSessionEMA, questionId: "stress", sessionType: "pre")
            let postStress = extractEMAValue(from: session.postSessionEMA, questionId: "stress", sessionType: "post")
            let preCalm = extractEMAValue(from: session.preSessionEMA, questionId: "calm", sessionType: "pre")
            let postCalm = extractEMAValue(from: session.postSessionEMA, questionId: "calm", sessionType: "post")
            
            // Extract focus quality from post-session EMA data (stored as both 'focus_quality' and 'accuracy')
            let focusQuality = extractFocusQuality(from: session.postSessionEMA)
            
            // FOCUS QUALITY DEBUG: Log extracted value
            print("PROGRESS_VIEW: [FOCUS_QUALITY_DEBUG] Session \(session.sessionDate) - Extracted focusQuality: \(focusQuality?.description ?? "nil")")
            
            return SessionData(
                date: session.sessionDate,
                preStress: preStress,
                postStress: postStress,
                preCalm: preCalm,
                postCalm: postCalm,
                focusQuality: focusQuality
            )
        }
    }
    
    private func extractEMAValue(from emaData: [String: Any], questionId: String, sessionType: String) -> Double? {
        // Build the correct key based on the session type and question ID
        let keyBase = "ema_\(sessionType)_session"
        let fullKey: String
        
        switch questionId {
        case "stress":
            fullKey = "\(keyBase)_stress"
        case "calm":
            fullKey = "\(keyBase)_calm_jittery"  // Fixed: calm maps to calm_jittery
        default:
            print("PROGRESS_VIEW: Unknown question ID '\(questionId)'")
            return nil
        }
        
        print("PROGRESS_VIEW: extractEMAValue for '\(questionId)' (\(sessionType)-session)")
        print("PROGRESS_VIEW: Looking for key: '\(fullKey)'")
        print("PROGRESS_VIEW: Available keys: \(Array(emaData.keys))")
        
        // Extract the value using the correct key
        if let value = emaData[fullKey] as? Double {
            print("PROGRESS_VIEW: Found Double value for '\(fullKey)': \(value)")
            return value
        } else if let value = emaData[fullKey] as? Int {
            print("PROGRESS_VIEW: Found Int value for '\(fullKey)': \(value)")
            return Double(value)
        } else if let value = emaData[fullKey] as? String, let doubleValue = Double(value) {
            print("PROGRESS_VIEW: Found String value for '\(fullKey)': \(value) -> \(doubleValue)")
            return doubleValue
        }
        
        print("PROGRESS_VIEW: No value found for '\(fullKey)' in EMA data")
        return nil
    }
    
    private func extractFocusQuality(from emaData: [String: Any]) -> Double? {
        // Focus quality data is stored in post-session EMA under both 'focus_quality' and 'accuracy' keys
        print("PROGRESS_VIEW: extractFocusQuality called")
        print("PROGRESS_VIEW: Available keys: \(Array(emaData.keys))")
        
        // First try 'focus_quality' key (newer format)
        if let value = emaData["focus_quality"] as? Double {
            print("PROGRESS_VIEW: Found focus_quality as Double: \(value)")
            return value
        } else if let value = emaData["focus_quality"] as? Int {
            print("PROGRESS_VIEW: Found focus_quality as Int: \(value)")
            return Double(value)
        } else if let value = emaData["focus_quality"] as? String, let doubleValue = Double(value) {
            print("PROGRESS_VIEW: Found focus_quality as String: \(value) -> \(doubleValue)")
            return doubleValue
        }
        
        // Fallback to 'accuracy' key (backward compatibility)
        if let value = emaData["accuracy"] as? Double {
            print("PROGRESS_VIEW: Found accuracy as Double: \(value)")
            return value
        } else if let value = emaData["accuracy"] as? Int {
            print("PROGRESS_VIEW: Found accuracy as Int: \(value)")
            return Double(value)
        } else if let value = emaData["accuracy"] as? String, let doubleValue = Double(value) {
            print("PROGRESS_VIEW: Found accuracy as String: \(value) -> \(doubleValue)")
            return doubleValue
        }
        
        print("PROGRESS_VIEW: No focus quality found in EMA data")
        return nil
    }
    
    private func updateUI() {
        if sessionData.isEmpty {
            // Show no data state
            stressChartView.isHidden = true
            calmChartView.isHidden = true
            focusQualityChartView.isHidden = true
            noDataLabel.isHidden = false
        } else {
            // Show charts with data
            stressChartView.isHidden = false
            calmChartView.isHidden = false
            focusQualityChartView.isHidden = false
            noDataLabel.isHidden = true
            
            // Update charts with current granularity
            let stressPreData = sessionData.compactMap { $0.preStress }
            let stressPostData = sessionData.compactMap { $0.postStress }
            stressChartView.updateData(preData: stressPreData, postData: stressPostData, dates: sessionData.map { $0.date }, granularity: currentGranularity)
            
            let calmPreData = sessionData.compactMap { $0.preCalm }
            let calmPostData = sessionData.compactMap { $0.postCalm }
            calmChartView.updateData(preData: calmPreData, postData: calmPostData, dates: sessionData.map { $0.date }, granularity: currentGranularity)
            
            // Focus quality chart uses empty arrays for pre-data since focus quality is only measured post-session
            let focusQualityData = sessionData.compactMap { $0.focusQuality }
            let emptyPreData: [Double] = []
            
            // FOCUS QUALITY DEBUG: Log final data being passed to chart
            print("PROGRESS_VIEW: [FOCUS_QUALITY_DEBUG] updateUI - Final focusQualityData: \(focusQualityData)")
            print("PROGRESS_VIEW: [FOCUS_QUALITY_DEBUG] updateUI - sessionData count: \(sessionData.count)")
            print("PROGRESS_VIEW: [FOCUS_QUALITY_DEBUG] updateUI - dates count: \(sessionData.map { $0.date }.count)")
            
            focusQualityChartView.updateData(preData: emptyPreData, postData: focusQualityData, dates: sessionData.map { $0.date }, granularity: currentGranularity)
        }
    }
    
    // MARK: - Actions
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func timeGranularityChanged() {
        print("PROGRESS_VIEW: timeGranularityChanged called")
        print("PROGRESS_VIEW: Selected segment index: \(timeGranularityControl.selectedSegmentIndex)")
        
        guard let newGranularity = TimeGranularity(rawValue: timeGranularityControl.selectedSegmentIndex) else { 
            print("PROGRESS_VIEW: ERROR - Invalid granularity index")
            return 
        }
        
        print("PROGRESS_VIEW: Granularity changing from \(currentGranularity.displayName) to \(newGranularity.displayName)")
        currentGranularity = newGranularity
        
        // Add defensive check for view hierarchy
        print("PROGRESS_VIEW: About to process data for new granularity")
        processDataForCurrentGranularity()
        
        print("PROGRESS_VIEW: Granularity change completed successfully")
    }
    
    // MARK: - Data Processing
    private func groupAndAverageData(_ data: [SessionData], by granularity: TimeGranularity) -> [SessionData] {
        guard !data.isEmpty else { 
            print("PROGRESS_VIEW: groupAndAverageData - No data to process")
            return [] 
        }
        
        print("PROGRESS_VIEW: groupAndAverageData - Processing \(data.count) sessions")
        
        // Sort data by date
        let sortedData = data.sorted { $0.date < $1.date }
        
        // Group data by time period using UTC timezone for consistency
        let calendar = Calendar.current
        var groupedData: [String: [SessionData]] = [:]
        
        for session in sortedData {
            let key: String
            
            switch granularity {
            case .daily:
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone(identifier: "UTC") // Use UTC for consistent grouping
                key = dateFormatter.string(from: session.date)
                
            case .weekly:
                let weekOfYear = calendar.component(.weekOfYear, from: session.date)
                let year = calendar.component(.year, from: session.date)
                key = "\(year)-W\(weekOfYear)"
                
            case .monthly:
                let month = calendar.component(.month, from: session.date)
                let year = calendar.component(.year, from: session.date)
                key = "\(year)-\(String(format: "%02d", month))"
            }
            
            print("PROGRESS_VIEW: Session date: \(session.date), Key: \(key)")
            
            if groupedData[key] == nil {
                groupedData[key] = []
            }
            groupedData[key]?.append(session)
        }
        
        print("PROGRESS_VIEW: Grouped into \(groupedData.count) distinct periods")
        
        // Average the grouped data
        var averagedData: [SessionData] = []
        
        for (key, sessions) in groupedData {
            guard !sessions.isEmpty else { continue }
            
            print("PROGRESS_VIEW: Processing group \(key) with \(sessions.count) sessions")
            
            // Use the first session's date as representative date for the group
            let representativeDate = sessions.first!.date
            
            // Calculate averages for each metric
            let preStressValues = sessions.compactMap { $0.preStress }
            let postStressValues = sessions.compactMap { $0.postStress }
            let preCalmValues = sessions.compactMap { $0.preCalm }
            let postCalmValues = sessions.compactMap { $0.postCalm }
            let focusQualityValues = sessions.compactMap { $0.focusQuality }
            
            // FOCUS QUALITY DEBUG: Log focus quality values before averaging
            print("PROGRESS_VIEW: [FOCUS_QUALITY_DEBUG] Group \(key) - focusQualityValues: \(focusQualityValues)")
            
            let avgPreStress = preStressValues.isEmpty ? nil : preStressValues.reduce(0, +) / Double(preStressValues.count)
            let avgPostStress = postStressValues.isEmpty ? nil : postStressValues.reduce(0, +) / Double(postStressValues.count)
            let avgPreCalm = preCalmValues.isEmpty ? nil : preCalmValues.reduce(0, +) / Double(preCalmValues.count)
            let avgPostCalm = postCalmValues.isEmpty ? nil : postCalmValues.reduce(0, +) / Double(postCalmValues.count)
            let avgFocusQuality = focusQualityValues.isEmpty ? nil : focusQualityValues.reduce(0, +) / Double(focusQualityValues.count)
            
            // FOCUS QUALITY DEBUG: Log averaged focus quality value
            print("PROGRESS_VIEW: [FOCUS_QUALITY_DEBUG] Group \(key) - avgFocusQuality: \(avgFocusQuality?.description ?? "nil")")
            
            print("PROGRESS_VIEW: Averages for \(key) - Stress: \(avgPreStress ?? 0)/\(avgPostStress ?? 0), Calm: \(avgPreCalm ?? 0)/\(avgPostCalm ?? 0), Focus Quality: \(avgFocusQuality ?? 0)")
            
            let averagedSession = SessionData(
                date: representativeDate,
                preStress: avgPreStress,
                postStress: avgPostStress,
                preCalm: avgPreCalm,
                postCalm: avgPostCalm,
                focusQuality: avgFocusQuality
            )
            
            averagedData.append(averagedSession)
        }
        
        // Sort by date and return
        let finalData = averagedData.sorted { $0.date < $1.date }
        print("PROGRESS_VIEW: Final processed data count: \(finalData.count)")
        return finalData
    }
    
    // MARK: - Helper Methods
    private func showLoading(_ show: Bool) {
        if show {
            loadingIndicator.startAnimating()
            mainStackView.alpha = 0.3
            view.isUserInteractionEnabled = false
        } else {
            loadingIndicator.stopAnimating()
            mainStackView.alpha = 1.0
            view.isUserInteractionEnabled = true
        }
    }
}

// MARK: - LineChartView
class LineChartView: UIView {
    
    private let titleLabel = UILabel()
    private let metricLabel = UILabel()
    private let legendStackView = UIStackView()
    private let chartContainerView = UIView()
    
    private var primaryColor: UIColor = .systemBlue
    private var secondaryColor: UIColor = .systemGray
    private var darkColor: UIColor = .black
    private var whiteColor: UIColor = .white
    
    private var preData: [Double] = []
    private var postData: [Double] = []
    private var dates: [Date] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = UIColor(white: 0.1, alpha: 0.3)
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 0.3, alpha: 0.5).cgColor
        
        let stackView = UIStackView(arrangedSubviews: [titleLabel, metricLabel, legendStackView, chartContainerView])
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        // Setup labels
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        
        metricLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        metricLabel.textAlignment = .center
        
        // Setup legend
        setupLegend()
        
        // Setup chart container
        chartContainerView.heightAnchor.constraint(equalToConstant: 160).isActive = true
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }
    
    private func setupLegend() {
        // Clear existing legend items to prevent duplication
        legendStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        legendStackView.axis = .horizontal
        legendStackView.distribution = .fillEqually
        legendStackView.spacing = 16
        
        let preLabel = createLegendLabel(text: "Pre-Session", color: secondaryColor)
        let postLabel = createLegendLabel(text: "Post-Session", color: primaryColor)
        
        legendStackView.addArrangedSubview(preLabel)
        legendStackView.addArrangedSubview(postLabel)
    }
    
    private func createLegendLabel(text: String, color: UIColor) -> UIView {
        let containerView = UIView()
        
        let circleView = UIView()
        circleView.backgroundColor = color
        circleView.layer.cornerRadius = 4
        circleView.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = whiteColor
        label.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(circleView)
        containerView.addSubview(label)
        
        NSLayoutConstraint.activate([
            circleView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            circleView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            circleView.widthAnchor.constraint(equalToConstant: 8),
            circleView.heightAnchor.constraint(equalToConstant: 8),
            
            label.leadingAnchor.constraint(equalTo: circleView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        
        return containerView
    }
    
    func configure(title: String, metric: String, primaryColor: UIColor, secondaryColor: UIColor, darkColor: UIColor, whiteColor: UIColor) {
        titleLabel.text = title
        titleLabel.textColor = whiteColor
        
        metricLabel.text = metric
        metricLabel.textColor = secondaryColor
        
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.darkColor = darkColor
        self.whiteColor = whiteColor
        
        setupLegend() // Refresh legend with new colors
    }
    
    func updateData(preData: [Double], postData: [Double], dates: [Date], granularity: TimeGranularity) {
        self.preData = preData
        self.postData = postData
        
        // Filter dates to only include those with corresponding data points
        // This ensures proper alignment between data and dates, especially for post-session-only metrics
        let dataPointCount = max(preData.count, postData.count)
        self.dates = Array(dates.prefix(dataPointCount))
        
        print("CHART: updateData - preData: \(preData.count), postData: \(postData.count), dates: \(self.dates.count)")
        
        // FOCUS QUALITY DEBUG: Add chart-specific logging
        if titleLabel.text == "Focus Quality" {
            print("CHART: [FOCUS_QUALITY_DEBUG] LineChartView.updateData called for Focus Quality chart")
            print("CHART: [FOCUS_QUALITY_DEBUG] Received postData: \(postData)")
            print("CHART: [FOCUS_QUALITY_DEBUG] Chart container bounds: \(chartContainerView.bounds)")
        }
        
        // Clear only the drawing layers synchronously, avoid any subview access
        chartContainerView.layer.sublayers = []
        
        // Redraw immediately without any async dispatch
        drawChart()
        addAxisLabels(granularity: granularity)
    }
    
    private func drawChart() {
        // Allow drawing even if only one dataset has data, but require at least one non-empty dataset
        guard !preData.isEmpty || !postData.isEmpty else { 
            print("CHART: Cannot draw - no data available")
            return 
        }
        
        // For charts with only post-data (like Focus Quality), use post-data count for layout
        let dataPointCount = max(preData.count, postData.count)
        guard dataPointCount > 0 else {
            print("CHART: Cannot draw - no data points")
            return
        }
        
        let chartBounds = chartContainerView.bounds
        guard chartBounds.width > 0 && chartBounds.height > 0 else { 
            print("CHART: Cannot draw - invalid bounds: \(chartBounds)")
            return 
        }
        
        let margin: CGFloat = 20
        let drawingRect = CGRect(
            x: margin,
            y: margin,
            width: chartBounds.width - 2 * margin,
            height: chartBounds.height - 2 * margin
        )
        
        // Calculate data ranges - use fixed 0-100 scale to match EMA input range
        let allValues = preData + postData
        guard !allValues.isEmpty else { 
            print("CHART: No values to draw")
            return 
        }
        
        let minValue = 0.0  // Fixed minimum value
        let maxValue = 100.0  // Fixed maximum value to match EMA slider range (0-100)
        let valueRange = maxValue - minValue
        
        print("CHART: Drawing with \(preData.count) points, range: \(minValue) - \(maxValue)")
        
        // Helper function to convert data point to screen coordinates
        func pointForData(index: Int, value: Double) -> CGPoint {
            let x: CGFloat
            if dataPointCount == 1 {
                // Center single point horizontally
                x = drawingRect.minX + drawingRect.width / 2
            } else {
                x = drawingRect.minX + (CGFloat(index) / CGFloat(dataPointCount - 1)) * drawingRect.width
            }
            let normalizedValue = valueRange > 0 ? (value - minValue) / valueRange : 0.5
            let y = drawingRect.maxY - CGFloat(normalizedValue) * drawingRect.height
            return CGPoint(x: x, y: y)
        }
        
        // Draw grid lines
        drawGrid(in: drawingRect, minValue: minValue, maxValue: maxValue)
        
        // Draw pre-session data
        if !preData.isEmpty {
            // Draw line only if more than one point
            if preData.count > 1 {
                let prePath = UIBezierPath()
                for (index, value) in preData.enumerated() {
                    let point = pointForData(index: index, value: value)
                    if index == 0 {
                        prePath.move(to: point)
                    } else {
                        prePath.addLine(to: point)
                    }
                }
                
                let preLineLayer = CAShapeLayer()
                preLineLayer.path = prePath.cgPath
                preLineLayer.strokeColor = secondaryColor.cgColor
                preLineLayer.lineWidth = 2
                preLineLayer.fillColor = UIColor.clear.cgColor
                chartContainerView.layer.addSublayer(preLineLayer)
            }
            
            // Always draw dots for pre-session data
            for (index, value) in preData.enumerated() {
                let point = pointForData(index: index, value: value)
                let dotLayer = CAShapeLayer()
                dotLayer.path = UIBezierPath(arcCenter: point, radius: 4, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
                dotLayer.fillColor = secondaryColor.cgColor
                chartContainerView.layer.addSublayer(dotLayer)
            }
        }
        
        // Draw post-session data
        if !postData.isEmpty {
            // Draw line only if more than one point
            if postData.count > 1 {
                let postPath = UIBezierPath()
                for (index, value) in postData.enumerated() {
                    let point = pointForData(index: index, value: value)
                    if index == 0 {
                        postPath.move(to: point)
                    } else {
                        postPath.addLine(to: point)
                    }
                }
                
                let postLineLayer = CAShapeLayer()
                postLineLayer.path = postPath.cgPath
                postLineLayer.strokeColor = primaryColor.cgColor
                postLineLayer.lineWidth = 2
                postLineLayer.fillColor = UIColor.clear.cgColor
                chartContainerView.layer.addSublayer(postLineLayer)
            }
            
            // Always draw dots for post-session data
            for (index, value) in postData.enumerated() {
                let point = pointForData(index: index, value: value)
                let dotLayer = CAShapeLayer()
                dotLayer.path = UIBezierPath(arcCenter: point, radius: 4, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
                dotLayer.fillColor = primaryColor.cgColor
                chartContainerView.layer.addSublayer(dotLayer)
            }
        }
        
        print("CHART: Successfully drew chart with pre: \(preData.count) points, post: \(postData.count) points")
    }
    
    private func drawGrid(in rect: CGRect, minValue: Double, maxValue: Double) {
        // Draw horizontal grid lines
        for i in 0...4 {
            let y = rect.minY + (CGFloat(i) / 4.0) * rect.height
            
            let gridPath = UIBezierPath()
            gridPath.move(to: CGPoint(x: rect.minX, y: y))
            gridPath.addLine(to: CGPoint(x: rect.maxX, y: y))
            
            let gridLayer = CAShapeLayer()
            gridLayer.path = gridPath.cgPath
            gridLayer.strokeColor = UIColor(white: 0.3, alpha: 0.3).cgColor
            gridLayer.lineWidth = 0.5
            chartContainerView.layer.addSublayer(gridLayer)
        }
        
        // Draw vertical grid lines
        let dataPointCount = max(preData.count, postData.count)
        let stepCount = min(dataPointCount - 1, 6)
        if stepCount > 0 {
            for i in 0...stepCount {
                let x = rect.minX + (CGFloat(i) / CGFloat(stepCount)) * rect.width
                
                let gridPath = UIBezierPath()
                gridPath.move(to: CGPoint(x: x, y: rect.minY))
                gridPath.addLine(to: CGPoint(x: x, y: rect.maxY))
                
                let gridLayer = CAShapeLayer()
                gridLayer.path = gridPath.cgPath
                gridLayer.strokeColor = UIColor(white: 0.3, alpha: 0.3).cgColor
                gridLayer.lineWidth = 0.5
                chartContainerView.layer.addSublayer(gridLayer)
            }
        }
    }
    
    private func addAxisLabels(granularity: TimeGranularity) {
        guard !dates.isEmpty && (!preData.isEmpty || !postData.isEmpty) else { return }
        
        let chartBounds = chartContainerView.bounds
        let margin: CGFloat = 20
        let drawingRect = CGRect(
            x: margin,
            y: margin,
            width: chartBounds.width - 2 * margin,
            height: chartBounds.height - 2 * margin
        )
        
        // Add Y-axis labels using fixed 0-100 scale to match EMA input range
        let minValue = 0.0  // Fixed minimum value
        let maxValue = 100.0  // Fixed maximum value to match EMA slider range (0-100)
        
        for i in 0...4 {
            let value = minValue + (maxValue - minValue) * Double(i) / 4.0
            let y = drawingRect.maxY - (CGFloat(i) / 4.0) * drawingRect.height
            
            let textLayer = CATextLayer()
            textLayer.string = String(format: "%.0f", value)
            textLayer.font = UIFont.systemFont(ofSize: 10, weight: .medium)
            textLayer.fontSize = 10
            textLayer.foregroundColor = secondaryColor.cgColor
            textLayer.alignmentMode = .right
            textLayer.contentsScale = UIScreen.main.scale
            
            // Position the text layer
            let textSize = CGSize(width: 30, height: 12)
            textLayer.frame = CGRect(x: margin - textSize.width - 5, y: y - textSize.height/2, width: textSize.width, height: textSize.height)
            
            chartContainerView.layer.addSublayer(textLayer)
        }
        
        // Add X-axis labels with dynamic skipping to prevent overcrowding
        let labelWidth: CGFloat = 50  // Estimated width needed per label including spacing
        let maxLabels = max(2, Int(drawingRect.width / labelWidth))  // Minimum 2 labels (start and end)
        let totalDataPoints = dates.count
        
        // Calculate stride for label skipping
        let stride = totalDataPoints <= maxLabels ? 1 : totalDataPoints / maxLabels
        
        print("CHART: Label skipping - Total points: \(totalDataPoints), Max labels: \(maxLabels), Stride: \(stride)")
        
        for (index, date) in dates.enumerated() {
            // Show label if it's at a stride interval, or if it's the first/last point
            let shouldShowLabel = (index % stride == 0) || (index == 0) || (index == totalDataPoints - 1)
            
            guard shouldShowLabel else { continue }
            
            let x: CGFloat
            if dates.count == 1 {
                x = drawingRect.minX + drawingRect.width / 2
            } else {
                x = drawingRect.minX + (CGFloat(index) / CGFloat(dates.count - 1)) * drawingRect.width
            }
            
            let labelText: String
            let dateFormatter = DateFormatter()
            
            switch granularity {
            case .daily:
                dateFormatter.dateFormat = "M/d"  // 8/19, 8/20, 12/31, etc.
                labelText = dateFormatter.string(from: date)
                
            case .weekly:
                let calendar = Calendar.current
                let weekOfYear = calendar.component(.weekOfYear, from: date)
                labelText = "W\(weekOfYear)"
                
            case .monthly:
                dateFormatter.dateFormat = "MMM"  // Aug, Sep, Oct, etc.
                labelText = dateFormatter.string(from: date)
            }
            
            let textLayer = CATextLayer()
            textLayer.string = labelText
            textLayer.font = UIFont.systemFont(ofSize: 10, weight: .medium)
            textLayer.fontSize = 10
            textLayer.foregroundColor = secondaryColor.cgColor
            textLayer.alignmentMode = .center
            textLayer.contentsScale = UIScreen.main.scale
            
            // Position the text layer
            let textSize = CGSize(width: 40, height: 12)
            textLayer.frame = CGRect(x: x - textSize.width/2, y: drawingRect.maxY + 5, width: textSize.width, height: textSize.height)
            
            chartContainerView.layer.addSublayer(textLayer)
        }
    }
}
