#if os(macOS)
import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    
    @State private var menuBarManager = MenuBarManager.shared
    @Query private var accounts: [SourceAccount]
    
    private var stats: MenuBarStats {
        menuBarManager.currentStats
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider()
            
            // Main metric
            mainMetricSection
            
            Divider()
            
            // Platform breakdown
            if !stats.platforms.isEmpty {
                platformsSection
                Divider()
            }
            
            // Error message if any
            if let error = menuBarManager.lastError {
                errorSection(error)
                Divider()
            }
            
            // Quick actions
            actionsSection
        }
        .frame(width: 300)
        .task {
            menuBarManager.start()
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Response Time")
                    .font(.headline)
                
                if let lastUpdate = menuBarManager.lastUpdate {
                    Text("Updated \(lastUpdate, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Not synced")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                Task {
                    await menuBarManager.refreshStats()
                }
            } label: {
                if menuBarManager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.plain)
            .disabled(menuBarManager.isLoading)
            .help("Refresh stats")
        }
        .padding()
    }
    
    // MARK: - Main Metric
    
    private var mainMetricSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Circle()
                    .fill(stats.statusColor)
                    .frame(width: 8, height: 8)
                Text(stats.formattedOverall)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            }
            
            Text("Median response time (7 days)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Pending responses badge
            if stats.totalPending > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .foregroundColor(.orange)
                    Text("\(stats.totalPending) pending response\(stats.totalPending == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.top, 4)
            }
            
            // Response count
            if stats.totalResponses > 0 {
                Text("\(stats.totalResponses) response\(stats.totalResponses == 1 ? "" : "s") tracked")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    // MARK: - Platforms Section
    
    private var platformsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BY PLATFORM")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 2)
            
            ForEach(stats.platforms) { platformStat in
                HStack {
                    Image(systemName: platformStat.platform.icon)
                        .foregroundColor(platformStat.platform.color)
                        .frame(width: 20)
                    
                    Text(platformStat.platform.displayName)
                        .font(.callout)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(platformStat.formattedLatency)
                            .font(.system(.callout, design: .monospaced))
                        
                        if platformStat.pendingCount > 0 {
                            Text("\(platformStat.pendingCount) pending")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            // Show unconnected platforms
            let connectedPlatforms = Set(stats.platforms.map(\.platform))
            let disconnectedPlatforms = Platform.allCases.filter { !connectedPlatforms.contains($0) }
            
            if !disconnectedPlatforms.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                
                ForEach(disconnectedPlatforms) { platform in
                    HStack {
                        Image(systemName: platform.icon)
                            .foregroundColor(.secondary.opacity(0.5))
                            .frame(width: 20)
                        
                        Text(platform.displayName)
                            .font(.callout)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("Not connected")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
        }
        .padding()
    }
    
    // MARK: - Error Section
    
    private func errorSection(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1))
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 4) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                // Open main window - the WindowGroup handles this
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
}

#Preview {
    MenuBarView()
        .environment(AppState())
        .modelContainer(for: [SourceAccount.self, ResponseWindow.self])
}
#endif
