import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentPage = 0
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Page content
            Group {
                switch currentPage {
                case 0: welcomePage
                case 1: privacyPage
                case 2: platformsPage
                default: completePage
                }
            }
            .animation(.easeInOut, value: currentPage)
            
            // Navigation
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        currentPage -= 1
                    }
                }
                
                Spacer()
                
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                if currentPage < 3 {
                    Button("Next") {
                        currentPage += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else if setupComplete {
                    Button("Open Dashboard") {
                        appState.isOnboarding = false
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else if hasPermission && !isSettingUp {
                    Button("Set Up & Sync") {
                        setupAndSync()
                    }
                    .buttonStyle(.borderedProminent)
                } else if !isSettingUp {
                    Button("Skip for Now") {
                        appState.isOnboarding = false
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 600, height: 500)
        #endif
    }
    
    // MARK: - Welcome Page
    
    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("Welcome to Response Time")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            
            Text("Track and improve your communication responsiveness across all your platforms")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Privacy Page
    
    private var privacyPage: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("Privacy First")
                .font(.largeTitle.bold())
            
            VStack(alignment: .leading, spacing: 16) {
                PrivacyFeatureRow(
                    icon: "desktopcomputer",
                    title: "100% Local Processing",
                    description: "All analysis happens on your device"
                )
                
                PrivacyFeatureRow(
                    icon: "eye.slash.fill",
                    title: "No Message Content",
                    description: "We only read timestamps, never your messages"
                )
                
                PrivacyFeatureRow(
                    icon: "icloud.slash",
                    title: "No Cloud Required",
                    description: "Your data stays on your device"
                )
                
                PrivacyFeatureRow(
                    icon: "hand.raised.fill",
                    title: "You're in Control",
                    description: "Delete your data anytime with one click"
                )
            }
            .padding(.horizontal, horizontalPadding)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Platforms Page
    
    private var platformsPage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Connect Your Platforms")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            
            Text("Response Time works with your favorite communication tools")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            #if os(macOS)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                platformPreviewCards
            }
            .padding(.horizontal, 32)
            #else
            LazyVStack(spacing: 12) {
                platformPreviewCards
            }
            .padding(.horizontal, 16)
            #endif
            
            Text("You can add or remove platforms anytime in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
    
    @ViewBuilder
    private var platformPreviewCards: some View {
        ForEach(Platform.allCases) { platform in
            PlatformPreviewCard(platform: platform)
        }
    }
    
    // MARK: - Complete Page
    
    @State private var hasPermission = false
    @State private var isSettingUp = false
    @State private var setupComplete = false
    
    private var completePage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if setupComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                Text("You're All Set!")
                    .font(.largeTitle.bold())
                
                Text("iMessage is connected and syncing. Your response time data will appear on the dashboard momentarily.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else if isSettingUp {
                ProgressView()
                    .controlSize(.large)
                
                Text("Setting up...")
                    .font(.title2.bold())
                
                Text("Creating iMessage connection and running first sync")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: hasPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 64))
                    .foregroundColor(hasPermission ? .green : .orange)
                
                Text(hasPermission ? "Ready to Go!" : "One More Step")
                    .font(.largeTitle.bold())
                
                if hasPermission {
                    Text("iMessage access is available. Tap below to set up and start tracking.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        NextStepRow(number: 1, text: "Auto-connect iMessage")
                        NextStepRow(number: 2, text: "Run first sync (timestamps only)")
                        NextStepRow(number: 3, text: "See your response time insights")
                    }
                    .padding(.horizontal, horizontalPadding)
                } else {
                    Text("Grant Full Disk Access so Response Time can read message timestamps (never content).")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    #if os(macOS)
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Check Again") {
                        checkPermissions()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    #endif
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear { checkPermissions() }
    }
    
    private func checkPermissions() {
        let testPath = NSHomeDirectory() + "/Library/Messages/chat.db"
        hasPermission = FileManager.default.isReadableFile(atPath: testPath)
    }
    
    private func setupAndSync() {
        isSettingUp = true
        Task {
            // Create iMessage account
            let account = SourceAccount(platform: .imessage, displayName: "iMessage", isEnabled: true)
            modelContext.insert(account)
            try? modelContext.save()
            
            // Run first sync
            do {
                try await iMessageSyncService.shared.syncToSwiftData(modelContext: modelContext)
            } catch {
                // Non-fatal — user can sync later
            }
            
            await MainActor.run {
                isSettingUp = false
                setupComplete = true
            }
        }
    }
    
    private var horizontalPadding: CGFloat {
        #if os(macOS)
        return 48
        #else
        return 24
        #endif
    }
}

// MARK: - Supporting Views

struct PrivacyFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PlatformPreviewCard: View {
    let platform: Platform
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(platform.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: platform.icon)
                    .foregroundColor(platform.color)
            }
            
            VStack(alignment: .leading) {
                Text(platform.displayName)
                    .font(.headline)
                Text(platformStatus(platform))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private func platformStatus(_ platform: Platform) -> String {
        switch platform {
        case .gmail: return "OAuth ready"
        case .outlook: return "OAuth ready"
        case .slack: return "OAuth ready"
        case .imessage: return "Requires permissions"
        }
    }
}

struct NextStepRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
}
