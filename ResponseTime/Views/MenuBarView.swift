import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    
    @Query private var accounts: [SourceAccount]
    @Query(sort: \ResponseWindow.computedAt, order: .reverse)
    private var recentResponses: [ResponseWindow]
    
    // Computed metrics (would come from analytics service)
    private var medianResponseTime: String {
        guard !recentResponses.isEmpty else { return "--" }
        // Simulated
        return "47m"
    }
    
    private var goalProgress: Double {
        // Simulated
        0.78
    }
    
    private var statusColor: Color {
        if goalProgress >= 0.8 { return .green }
        if goalProgress >= 0.6 { return .yellow }
        return .red
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Response Time")
                        .font(.headline)
                    Text(appState.lastSyncDate.map { "Updated \($0, style: .relative)" } ?? "Not synced")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    Task { await sync() }
                } label: {
                    if appState.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.plain)
                .disabled(appState.isSyncing)
            }
            .padding()
            
            Divider()
            
            // Main metric
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(medianResponseTime)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                }
                
                Text("Median response time this week")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Goal progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(statusColor)
                            .frame(width: geo.size.width * goalProgress)
                    }
                }
                .frame(height: 6)
                
                Text("\(Int(goalProgress * 100))% within target")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Platform breakdown
            if !accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(accounts) { account in
                        HStack {
                            Image(systemName: account.platform.icon)
                                .foregroundColor(account.platform.color)
                                .frame(width: 20)
                            
                            Text(account.platform.displayName)
                                .font(.callout)
                            
                            Spacer()
                            
                            Text("1h 12m")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                
                Divider()
            }
            
            // Quick actions
            VStack(spacing: 4) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    // Would open main window
                } label: {
                    HStack {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        Text("Open Dashboard")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 6)
                
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text("Settings...")
                        Spacer()
                        Text("⌘,")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 6)
                
                Divider()
                    .padding(.vertical, 4)
                
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text("Quit Response Time")
                        Spacer()
                        Text("⌘Q")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }
    
    private func sync() async {
        appState.isSyncing = true
        defer { appState.isSyncing = false }
        
        try? await Task.sleep(for: .seconds(1))
        appState.lastSyncDate = Date()
    }
}

#Preview {
    MenuBarView()
        .environment(AppState())
        .modelContainer(for: [SourceAccount.self, ResponseWindow.self])
}
