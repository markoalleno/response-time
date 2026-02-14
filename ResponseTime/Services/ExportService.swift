import Foundation
import SwiftData
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

// MARK: - Export Service

@MainActor
class ExportService {
    static let shared = ExportService()
    
    enum ExportFormat {
        case csv
        case json
    }
    
    struct ExportResult {
        let data: Data
        let filename: String
        let mimeType: String
    }
    
    // MARK: - Export Response Data
    
    func exportResponseData(
        windows: [ResponseWindow],
        format: ExportFormat = .csv
    ) -> ExportResult {
        switch format {
        case .csv:
            return exportAsCSV(windows: windows)
        case .json:
            return exportAsJSON(windows: windows)
        }
    }
    
    private func exportAsCSV(windows: [ResponseWindow]) -> ExportResult {
        var csv = "date,time,platform,from,subject,response_time_seconds,response_time_formatted,confidence,matching_method\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        
        for window in windows.sorted(by: { ($0.inboundEvent?.timestamp ?? .distantPast) > ($1.inboundEvent?.timestamp ?? .distantPast) }) {
            guard let inbound = window.inboundEvent else { continue }
            
            let date = dateFormatter.string(from: inbound.timestamp)
            let time = timeFormatter.string(from: inbound.timestamp)
            let platform = inbound.conversation?.sourceAccount?.platform.displayName ?? "Unknown"
            let from = escapeCSV(inbound.participantEmail)
            let subject = escapeCSV(inbound.conversation?.subject ?? "")
            let seconds = Int(window.latencySeconds)
            let formatted = formatDuration(window.latencySeconds)
            let confidence = String(format: "%.2f", window.confidence)
            let method = window.matchingMethod.rawValue
            
            csv += "\(date),\(time),\(platform),\(from),\(subject),\(seconds),\(formatted),\(confidence),\(method)\n"
        }
        
        return ExportResult(
            data: Data(csv.utf8),
            filename: "response-time-export-\(dateFormatter.string(from: Date())).csv",
            mimeType: "text/csv"
        )
    }
    
    private func exportAsJSON(windows: [ResponseWindow]) -> ExportResult {
        let exportData = windows.map { window -> [String: Any] in
            [
                "timestamp": window.inboundEvent?.timestamp.timeIntervalSince1970 ?? 0,
                "platform": window.inboundEvent?.conversation?.sourceAccount?.platform.rawValue ?? "unknown",
                "from": window.inboundEvent?.participantEmail ?? "",
                "subject": window.inboundEvent?.conversation?.subject ?? "",
                "response_time_seconds": window.latencySeconds,
                "confidence": window.confidence,
                "matching_method": window.matchingMethod.rawValue
            ]
        }
        
        let wrapper: [String: Any] = [
            "export_date": ISO8601DateFormatter().string(from: Date()),
            "total_records": windows.count,
            "data": exportData
        ]
        
        let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys])
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        return ExportResult(
            data: data ?? Data(),
            filename: "response-time-export-\(dateFormatter.string(from: Date())).json",
            mimeType: "application/json"
        )
    }
    
    // MARK: - Export Summary Report
    
    func exportSummaryReport(
        metrics: ResponseMetrics,
        dailyData: [DailyMetrics],
        goals: [ResponseGoal]
    ) -> ExportResult {
        var report = """
        # Response Time Summary Report
        Generated: \(ISO8601DateFormatter().string(from: Date()))
        
        ## Overview
        - Time Period: \(metrics.timeRange.displayName)
        - Total Samples: \(metrics.sampleCount)
        
        ## Response Time Metrics
        - Median: \(metrics.formattedMedian)
        - Mean: \(metrics.formattedMean)
        - 90th Percentile: \(metrics.formattedP90)
        - Minimum: \(formatDuration(metrics.minLatency))
        - Maximum: \(formatDuration(metrics.maxLatency))
        
        """
        
        if let workingHours = metrics.workingHoursMedian,
           let nonWorkingHours = metrics.nonWorkingHoursMedian {
            report += """
            
            ## Working Hours Analysis
            - During Working Hours: \(formatDuration(workingHours))
            - Outside Working Hours: \(formatDuration(nonWorkingHours))
            
            """
        }
        
        if let trend = metrics.trendPercentage {
            let direction = trend < 0 ? "improved" : "declined"
            report += """
            
            ## Trend
            - Response times have \(direction) by \(abs(Int(trend)))% compared to the previous period.
            
            """
        }
        
        if !goals.isEmpty {
            report += """
            
            ## Goals
            """
            for goal in goals {
                let platform = goal.platform?.displayName ?? "All Platforms"
                report += "- \(platform): \(goal.formattedTarget)\n"
            }
        }
        
        if !dailyData.isEmpty {
            report += """
            
            ## Daily Breakdown
            Date,Median,Responses
            """
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            for day in dailyData.sorted(by: { $0.date > $1.date }) {
                report += "\n\(dateFormatter.string(from: day.date)),\(formatDuration(day.medianLatency)),\(day.responseCount)"
            }
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        return ExportResult(
            data: Data(report.utf8),
            filename: "response-time-report-\(dateFormatter.string(from: Date())).md",
            mimeType: "text/markdown"
        )
    }
    
    // MARK: - Helpers
    
    private func escapeCSV(_ string: String) -> String {
        var escaped = string.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            escaped = "\"\(escaped)\""
        }
        return escaped
    }
    
    #if os(iOS)
    func shareExport(_ result: ExportResult, from viewController: UIViewController) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(result.filename)
        try? result.data.write(to: tempURL)
        
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        viewController.present(activityVC, animated: true)
    }
    #endif
    
    #if os(macOS)
    func saveExport(_ result: ExportResult) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = result.filename
        
        if result.mimeType == "text/csv" {
            panel.allowedContentTypes = [UTType.commaSeparatedText]
        } else if result.mimeType == "application/json" {
            panel.allowedContentTypes = [UTType.json]
        } else {
            panel.allowedContentTypes = [UTType.plainText]
        }
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? result.data.write(to: url)
            }
        }
    }
    #endif
}
