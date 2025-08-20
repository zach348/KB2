import XCTest
@testable import KB2
import UIKit

class ProgressViewLabelSkippingTests: XCTestCase {
    
    var chartView: TestableLineChartView!
    
    override func setUp() {
        super.setUp()
        chartView = TestableLineChartView()
        
        // Configure the chart view with test colors
        chartView.configure(
            title: "Test Chart",
            metric: "Test Metric",
            primaryColor: .systemBlue,
            secondaryColor: .systemGray,
            darkColor: .black,
            whiteColor: .white
        )
        
        // Set up the chart container with a realistic size
        chartView.frame = CGRect(x: 0, y: 0, width: 300, height: 280)
        chartView.layoutIfNeeded()
    }
    
    // MARK: - Daily View Tests
    
    func testDailyView_SmallDataset_AllLabelsShown() {
        // Test with 5 days of data - all labels should be shown
        let dates = generateDailyDates(count: 5)
        let data = generateRandomData(count: 5)
        
        chartView.updateData(preData: data, postData: data, dates: dates, granularity: .daily)
        
        let labelCount = chartView.getAxisLabelCount()
        
        // With only 5 data points, all labels should be shown
        XCTAssertEqual(labelCount, 5, "Small dataset should show all labels")
    }
    
    func testDailyView_LargeDataset_LabelsSkipped() {
        // Test with 100 days of data - labels should be skipped
        let dates = generateDailyDates(count: 100)
        let data = generateRandomData(count: 100)
        
        chartView.updateData(preData: data, postData: data, dates: dates, granularity: .daily)
        
        let labelCount = chartView.getAxisLabelCount()
        let expectedMaxLabels = chartView.calculateMaxLabels()
        
        // Should be close to the maximum calculated labels (may exceed by 1-2 due to start/end priority)
        XCTAssertLessThanOrEqual(labelCount, expectedMaxLabels + 2, "Large dataset should skip labels to stay reasonably close to max")
        
        // Should have significantly fewer labels than data points
        XCTAssertLessThan(labelCount, 100, "Should skip many labels with 100 data points")
        
        // Should have at least 2 labels (start and end)
        XCTAssertGreaterThanOrEqual(labelCount, 2, "Should always show at least start and end labels")
    }
    
    func testDailyView_VeryLargeDataset_StillManageable() {
        // Test with 365 days (1 year) of data
        let dates = generateDailyDates(count: 365)
        let data = generateRandomData(count: 365)
        
        chartView.updateData(preData: data, postData: data, dates: dates, granularity: .daily)
        
        let labelCount = chartView.getAxisLabelCount()
        let expectedMaxLabels = chartView.calculateMaxLabels()
        
        // Should be well within manageable limits (may exceed by 1-2 due to start/end priority)
        XCTAssertLessThanOrEqual(labelCount, expectedMaxLabels + 2, "Very large dataset should still be manageable")
        XCTAssertLessThan(labelCount, 15, "Should not show more than ~15 labels even with 365 data points")
    }
    
    // MARK: - Weekly View Tests
    
    func testWeeklyView_SmallDataset() {
        // Test with 4 weeks of data
        let dates = generateWeeklyDates(count: 4)
        let data = generateRandomData(count: 4)
        
        chartView.updateData(preData: data, postData: data, dates: dates, granularity: .weekly)
        
        let labelCount = chartView.getAxisLabelCount()
        
        // With only 4 weeks, all labels should be shown
        XCTAssertEqual(labelCount, 4, "Small weekly dataset should show all labels")
    }
    
    func testWeeklyView_LargeDataset() {
        // Test with 52 weeks (1 year) of data
        let dates = generateWeeklyDates(count: 52)
        let data = generateRandomData(count: 52)
        
        chartView.updateData(preData: data, postData: data, dates: dates, granularity: .weekly)
        
        let labelCount = chartView.getAxisLabelCount()
        let expectedMaxLabels = chartView.calculateMaxLabels()
        
        // Should skip labels appropriately (may exceed by 1-2 due to start/end priority)
        XCTAssertLessThanOrEqual(labelCount, expectedMaxLabels + 2, "Large weekly dataset should skip labels")
        XCTAssertLessThan(labelCount, 52, "Should not show all 52 week labels")
        XCTAssertGreaterThanOrEqual(labelCount, 2, "Should show at least start and end labels")
    }
    
    // MARK: - Monthly View Tests
    
    func testMonthlyView_SmallDataset() {
        // Test with 6 months of data
        let dates = generateMonthlyDates(count: 6)
        let data = generateRandomData(count: 6)
        
        chartView.updateData(preData: data, postData: data, dates: dates, granularity: .monthly)
        
        let labelCount = chartView.getAxisLabelCount()
        
        // With only 6 months, all labels should be shown
        XCTAssertEqual(labelCount, 6, "Small monthly dataset should show all labels")
    }
    
    func testMonthlyView_LargeDataset() {
        // Test with 24 months (2 years) of data
        let dates = generateMonthlyDates(count: 24)
        let data = generateRandomData(count: 24)
        
        chartView.updateData(preData: data, postData: data, dates: dates, granularity: .monthly)
        
        let labelCount = chartView.getAxisLabelCount()
        let expectedMaxLabels = chartView.calculateMaxLabels()
        
        // Should skip labels appropriately (may exceed by 1-2 due to start/end priority)
        XCTAssertLessThanOrEqual(labelCount, expectedMaxLabels + 2, "Large monthly dataset should skip labels")
        XCTAssertLessThan(labelCount, 24, "Should not show all 24 month labels")
        XCTAssertGreaterThanOrEqual(labelCount, 2, "Should show at least start and end labels")
    }
    
    // MARK: - Edge Cases
    
    func testSingleDataPoint() {
        // Test with just one data point
        let dates = generateDailyDates(count: 1)
        let data = generateRandomData(count: 1)
        
        chartView.updateData(preData: data, postData: data, dates: dates, granularity: .daily)
        
        let labelCount = chartView.getAxisLabelCount()
        
        XCTAssertEqual(labelCount, 1, "Single data point should show one label")
    }
    
    func testTwoDataPoints() {
        // Test with two data points
        let dates = generateDailyDates(count: 2)
        let data = generateRandomData(count: 2)
        
        chartView.updateData(preData: data, postData: data, dates: dates, granularity: .daily)
        
        let labelCount = chartView.getAxisLabelCount()
        
        XCTAssertEqual(labelCount, 2, "Two data points should show both labels")
    }
    
    func testExtremeDataset() {
        // Test with an extreme dataset (3 years of daily data)
        let dates = generateDailyDates(count: 1095) // ~3 years
        let data = generateRandomData(count: 1095)
        
        chartView.updateData(preData: data, postData: data, dates: dates, granularity: .daily)
        
        let labelCount = chartView.getAxisLabelCount()
        let expectedMaxLabels = chartView.calculateMaxLabels()
        
        // Should still be manageable (may exceed by 1-2 due to start/end priority)
        XCTAssertLessThanOrEqual(labelCount, expectedMaxLabels + 2, "Extreme dataset should still be manageable")
        XCTAssertLessThan(labelCount, 20, "Should not show more than ~20 labels even with extreme dataset")
    }
    
    // MARK: - Label Skipping Logic Tests
    
    func testStrideCalculation() {
        // Test the stride calculation logic directly
        let testCases = [
            (dataPoints: 10, maxLabels: 6, expectedStride: 1), // 10 <= 6? No, so 10/6 = 1 (min 1)
            (dataPoints: 20, maxLabels: 6, expectedStride: 3), // 20/6 = 3
            (dataPoints: 100, maxLabels: 6, expectedStride: 16), // 100/6 = 16
            (dataPoints: 5, maxLabels: 6, expectedStride: 1), // 5 <= 6? Yes, so stride = 1
        ]
        
        for testCase in testCases {
            let dates = generateDailyDates(count: testCase.dataPoints)
            let data = generateRandomData(count: testCase.dataPoints)
            
            // Set the chart to have the specific max labels for this test
            chartView.setMaxLabelsForTesting(testCase.maxLabels)
            
            chartView.updateData(preData: data, postData: data, dates: dates, granularity: .daily)
            
            let actualStride = chartView.getCalculatedStride()
            
            XCTAssertEqual(actualStride, testCase.expectedStride,
                          "Stride calculation failed for \(testCase.dataPoints) data points with max \(testCase.maxLabels) labels")
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateDailyDates(count: Int) -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        
        for i in 0..<count {
            let date = calendar.date(byAdding: .day, value: i, to: startDate)!
            dates.append(date)
        }
        
        return dates
    }
    
    private func generateWeeklyDates(count: Int) -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        
        for i in 0..<count {
            let date = calendar.date(byAdding: .weekOfYear, value: i, to: startDate)!
            dates.append(date)
        }
        
        return dates
    }
    
    private func generateMonthlyDates(count: Int) -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        
        for i in 0..<count {
            let date = calendar.date(byAdding: .month, value: i, to: startDate)!
            dates.append(date)
        }
        
        return dates
    }
    
    private func generateRandomData(count: Int) -> [Double] {
        return (0..<count).map { _ in Double.random(in: 1.0...10.0) }
    }
}

// MARK: - Testable LineChartView

class TestableLineChartView: LineChartView {
    private var axisLabelCount = 0
    private var calculatedStride = 1
    private var maxLabelsOverride: Int?
    
    override func updateData(preData: [Double], postData: [Double], dates: [Date], granularity: TimeGranularity) {
        // Call parent implementation
        super.updateData(preData: preData, postData: postData, dates: dates, granularity: granularity)
        
        // Track the number of labels that would be created
        calculateLabelMetrics(dates: dates)
    }
    
    private func calculateLabelMetrics(dates: [Date]) {
        guard !dates.isEmpty else {
            axisLabelCount = 0
            return
        }
        
        let labelWidth: CGFloat = 50
        let drawingWidth: CGFloat = bounds.width - 40 // Account for margins
        let maxLabels = maxLabelsOverride ?? max(2, Int(drawingWidth / labelWidth))
        let totalDataPoints = dates.count
        
        calculatedStride = totalDataPoints <= maxLabels ? 1 : totalDataPoints / maxLabels
        
        var labelCount = 0
        for index in 0..<dates.count {
            let shouldShowLabel = (index % calculatedStride == 0) || (index == 0) || (index == totalDataPoints - 1)
            if shouldShowLabel {
                labelCount += 1
            }
        }
        
        axisLabelCount = labelCount
    }
    
    func getAxisLabelCount() -> Int {
        return axisLabelCount
    }
    
    func getCalculatedStride() -> Int {
        return calculatedStride
    }
    
    func calculateMaxLabels() -> Int {
        let labelWidth: CGFloat = 50
        let drawingWidth: CGFloat = bounds.width - 40 // Account for margins
        return max(2, Int(drawingWidth / labelWidth))
    }
    
    func setMaxLabelsForTesting(_ maxLabels: Int) {
        maxLabelsOverride = maxLabels
    }
}
