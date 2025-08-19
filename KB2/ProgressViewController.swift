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
    let preEnergy: Double?
    let postEnergy: Double?
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
    private let energyChartView = LineChartView()
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
        setupUI()
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
        setupChartView(calmChartView, title: "Calm Level", metric: "Higher is better") 
        setupChartView(energyChartView, title: "Energy Level", metric: "Track your vitality")
        
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
        mainStackView.addArrangedSubview(energyChartView)
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
        showLoading(true)
        
        // Get historical EMA data from DataLogger
        DataLogger.shared.getHistoricalEMAData { [weak self] historicalData in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.showLoading(false)
                self.rawHistoricalData = historicalData
                self.processDataForCurrentGranularity()
                
                if historicalData.isEmpty {
                    print("PROGRESS_VIEW: No historical EMA data found")
                } else {
                    print("PROGRESS_VIEW: Loaded \(historicalData.count) historical sessions")
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
            // Extract EMA values from the stored responses
            let preStress = extractEMAValue(from: session.preSessionEMA, questionId: "stress")
            let postStress = extractEMAValue(from: session.postSessionEMA, questionId: "stress")
            let preCalm = extractEMAValue(from: session.preSessionEMA, questionId: "calm")
            let postCalm = extractEMAValue(from: session.postSessionEMA, questionId: "calm")
            let preEnergy = extractEMAValue(from: session.preSessionEMA, questionId: "energy")
            let postEnergy = extractEMAValue(from: session.postSessionEMA, questionId: "energy")
            
            return SessionData(
                date: session.sessionDate,
                preStress: preStress,
                postStress: postStress,
                preCalm: preCalm,
                postCalm: postCalm,
                preEnergy: preEnergy,
                postEnergy: postEnergy
            )
        }
    }
    
    private func extractEMAValue(from emaData: [String: Any], questionId: String) -> Double? {
        // Handle both direct values and nested response structures
        if let value = emaData[questionId] as? Double {
            return value
        } else if let value = emaData[questionId] as? Int {
            return Double(value)
        } else if let value = emaData[questionId] as? String, let doubleValue = Double(value) {
            return doubleValue
        }
        return nil
    }
    
    private func updateUI() {
        if sessionData.isEmpty {
            // Show no data state
            stressChartView.isHidden = true
            calmChartView.isHidden = true
            energyChartView.isHidden = true
            noDataLabel.isHidden = false
        } else {
            // Show charts with data
            stressChartView.isHidden = false
            calmChartView.isHidden = false
            energyChartView.isHidden = false
            noDataLabel.isHidden = true
            
            // Update charts
            let stressPreData = sessionData.compactMap { $0.preStress }
            let stressPostData = sessionData.compactMap { $0.postStress }
            stressChartView.updateData(preData: stressPreData, postData: stressPostData, dates: sessionData.map { $0.date })
            
            let calmPreData = sessionData.compactMap { $0.preCalm }
            let calmPostData = sessionData.compactMap { $0.postCalm }
            calmChartView.updateData(preData: calmPreData, postData: calmPostData, dates: sessionData.map { $0.date })
            
            let energyPreData = sessionData.compactMap { $0.preEnergy }
            let energyPostData = sessionData.compactMap { $0.postEnergy }
            energyChartView.updateData(preData: energyPreData, postData: energyPostData, dates: sessionData.map { $0.date })
        }
    }
    
    // MARK: - Actions
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func timeGranularityChanged() {
        guard let newGranularity = TimeGranularity(rawValue: timeGranularityControl.selectedSegmentIndex) else { return }
        
        currentGranularity = newGranularity
        processDataForCurrentGranularity()
        
        print("PROGRESS_VIEW: Granularity changed to \(newGranularity.displayName)")
    }
    
    // MARK: - Data Processing
    private func groupAndAverageData(_ data: [SessionData], by granularity: TimeGranularity) -> [SessionData] {
        guard !data.isEmpty else { return [] }
        
        // Sort data by date
        let sortedData = data.sorted { $0.date < $1.date }
        
        // Group data by time period
        let calendar = Calendar.current
        var groupedData: [String: [SessionData]] = [:]
        
        for session in sortedData {
            let key: String
            
            switch granularity {
            case .daily:
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
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
            
            if groupedData[key] == nil {
                groupedData[key] = []
            }
            groupedData[key]?.append(session)
        }
        
        // Average the grouped data
        var averagedData: [SessionData] = []
        
        for (_, sessions) in groupedData {
            guard !sessions.isEmpty else { continue }
            
            // Use the first session's date as representative date for the group
            let representativeDate = sessions.first!.date
            
            // Calculate averages for each metric
            let preStressValues = sessions.compactMap { $0.preStress }
            let postStressValues = sessions.compactMap { $0.postStress }
            let preCalmValues = sessions.compactMap { $0.preCalm }
            let postCalmValues = sessions.compactMap { $0.postCalm }
            let preEnergyValues = sessions.compactMap { $0.preEnergy }
            let postEnergyValues = sessions.compactMap { $0.postEnergy }
            
            let avgPreStress = preStressValues.isEmpty ? nil : preStressValues.reduce(0, +) / Double(preStressValues.count)
            let avgPostStress = postStressValues.isEmpty ? nil : postStressValues.reduce(0, +) / Double(postStressValues.count)
            let avgPreCalm = preCalmValues.isEmpty ? nil : preCalmValues.reduce(0, +) / Double(preCalmValues.count)
            let avgPostCalm = postCalmValues.isEmpty ? nil : postCalmValues.reduce(0, +) / Double(postCalmValues.count)
            let avgPreEnergy = preEnergyValues.isEmpty ? nil : preEnergyValues.reduce(0, +) / Double(preEnergyValues.count)
            let avgPostEnergy = postEnergyValues.isEmpty ? nil : postEnergyValues.reduce(0, +) / Double(postEnergyValues.count)
            
            let averagedSession = SessionData(
                date: representativeDate,
                preStress: avgPreStress,
                postStress: avgPostStress,
                preCalm: avgPreCalm,
                postCalm: avgPostCalm,
                preEnergy: avgPreEnergy,
                postEnergy: avgPostEnergy
            )
            
            averagedData.append(averagedSession)
        }
        
        // Sort by date and return
        return averagedData.sorted { $0.date < $1.date }
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
    
    func updateData(preData: [Double], postData: [Double], dates: [Date]) {
        self.preData = preData
        self.postData = postData
        self.dates = dates
        
        setNeedsDisplay()
        
        // Remove existing chart layer and redraw
        chartContainerView.layer.sublayers?.removeAll()
        DispatchQueue.main.async {
            self.drawChart()
        }
    }
    
    private func drawChart() {
        guard !preData.isEmpty && !postData.isEmpty && preData.count == postData.count else { return }
        
        let chartBounds = chartContainerView.bounds
        guard chartBounds.width > 0 && chartBounds.height > 0 else { return }
        
        let margin: CGFloat = 20
        let drawingRect = CGRect(
            x: margin,
            y: margin,
            width: chartBounds.width - 2 * margin,
            height: chartBounds.height - 2 * margin
        )
        
        // Calculate data ranges
        let allValues = preData + postData
        let minValue = allValues.min() ?? 0
        let maxValue = allValues.max() ?? 10
        let valueRange = maxValue - minValue
        
        // Helper function to convert data point to screen coordinates
        func pointForData(index: Int, value: Double) -> CGPoint {
            let x = drawingRect.minX + (CGFloat(index) / CGFloat(preData.count - 1)) * drawingRect.width
            let normalizedValue = valueRange > 0 ? (value - minValue) / valueRange : 0.5
            let y = drawingRect.maxY - CGFloat(normalizedValue) * drawingRect.height
            return CGPoint(x: x, y: y)
        }
        
        // Draw grid lines
        drawGrid(in: drawingRect, minValue: minValue, maxValue: maxValue)
        
        // Draw pre-session line
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
            
            // Add dots for pre-session data
            for (index, value) in preData.enumerated() {
                let point = pointForData(index: index, value: value)
                let dotLayer = CAShapeLayer()
                dotLayer.path = UIBezierPath(arcCenter: point, radius: 3, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
                dotLayer.fillColor = secondaryColor.cgColor
                chartContainerView.layer.addSublayer(dotLayer)
            }
        }
        
        // Draw post-session line
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
            
            // Add dots for post-session data
            for (index, value) in postData.enumerated() {
                let point = pointForData(index: index, value: value)
                let dotLayer = CAShapeLayer()
                dotLayer.path = UIBezierPath(arcCenter: point, radius: 3, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
                dotLayer.fillColor = primaryColor.cgColor
                chartContainerView.layer.addSublayer(dotLayer)
            }
        }
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
        let stepCount = min(preData.count - 1, 6)
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
}
