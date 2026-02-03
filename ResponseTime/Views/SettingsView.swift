import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage("workingHoursStart") private var workingHoursStart = 9
    @AppStorage("workingHoursEnd") private var workingHoursEnd = 17
    @AppStorage("excludeWeekends") private var excludeWeekends = true
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("syncInBackground") private var syncInBackground = false
    @AppStorage("syncIntervalMinutes") private var syncIntervalMinutes = 30
    @AppStorage("matchingWindowDays") private var matchingWindowDays = 7
    @AppStorage("confidenceThreshold") private var confidenceThreshold = 0.7
    
    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            analyticsSettings
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
            
            privacySettings
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
            
            aboutView
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
    
    // MARK: - General Settings
    
    private var generalSettings: some View {
        Form {
            Section {
                Toggle("Show in Menu Bar", isOn: $showMenuBarIcon)
                Toggle("Sync in Background", isOn: $syncInBackground)
                
                if syncInBackground {
                    Picker("Sync Interval", selection: $syncIntervalMinutes) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                }
            } header: {
                Text("App Behavior")
            }
            
            Section {
                Picker("Start of Day", selection: $workingHoursStart) {
                    ForEach(0..<24) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
                
                Picker("End of Day", selection: $workingHoursEnd) {
                    ForEach(0..<24) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
                
                Toggle("Exclude Weekends from Working Hours", isOn: $excludeWeekends)
            } header: {
                Text("Working Hours")
            } footer: {
                Text("Working hours are used to calculate separate metrics for on vs off hours.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(from: DateComponents(hour: hour))!
        return formatter.string(from: date)
    }
    
    // MARK: - Analytics Settings
    
    private var analyticsSettings: some View {
        Form {
            Section {
                Picker("Matching Window", selection: $matchingWindowDays) {
                    Text("3 days").tag(3)
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
                
                VStack(alignment: .leading) {
                    Text("Confidence Threshold: \(Int(confidenceThreshold * 100))%")
                    Slider(value: $confidenceThreshold, in: 0.5...1.0, step: 0.05)
                }
            } header: {
                Text("Response Matching")
            } footer: {
                Text("Matching window determines how long after receiving a message we'll look for your response. Higher confidence thresholds require stronger thread matching.")
            }
            
            Section {
                Button("Reset Analytics") {
                    // Would reset all response windows
                }
                .foregroundColor(.red)
            } header: {
                Text("Data Management")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - Privacy Settings
    
    private var privacySettings: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Local Processing Only", systemImage: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("All data is processed and stored on your device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("No Message Content", systemImage: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("We only access timestamps and participant metadata")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("No Cloud Analytics", systemImage: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("No data is sent to external servers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Privacy Guarantees")
            }
            
            Section {
                Button("Export All Data (CSV)") {
                    exportData()
                }
                
                Button("Delete All Data") {
                    // Would delete all data
                }
                .foregroundColor(.red)
            } header: {
                Text("Your Data")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func exportData() {
        // Would export all response data to CSV
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "response-time-export.csv"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Export logic here
                let csv = "date,platform,from,response_time_minutes\n"
                try? csv.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    // MARK: - About View
    
    private var aboutView: some View {
        VStack(spacing: 24) {
            // App icon
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 4) {
                Text("Response Time")
                    .font(.title.bold())
                Text("Version 1.0")
                    .foregroundColor(.secondary)
            }
            
            Text("Privacy-first response time analytics for your communications.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Divider()
            
            VStack(spacing: 8) {
                Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                Link("Support", destination: URL(string: "mailto:support@example.com")!)
            }
            
            Spacer()
            
            Text("© 2025 Mark Allen")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(32)
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
