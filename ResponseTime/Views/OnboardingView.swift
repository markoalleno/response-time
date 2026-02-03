import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentPage = 0
    
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
                    ForEach(0..<4) { index in
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
                } else {
                    Button("Get Started") {
                        appState.isOnboarding = false
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 500)
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
                    description: "All analysis happens on your Mac"
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
            .padding(.horizontal, 48)
            
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
            
            Text("Response Time works with your favorite communication tools")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(Platform.allCases) { platform in
                    PlatformPreviewCard(platform: platform)
                }
            }
            .padding(.horizontal, 32)
            
            Text("You can add or remove platforms anytime in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Complete Page
    
    private var completePage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("You're All Set!")
                .font(.largeTitle.bold())
            
            Text("Connect a platform to start tracking your response times")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 12) {
                NextStepRow(
                    number: 1,
                    text: "Connect your first platform (Gmail, Outlook, or Slack)"
                )
                NextStepRow(
                    number: 2,
                    text: "Wait for initial sync to complete"
                )
                NextStepRow(
                    number: 3,
                    text: "View your response time insights on the dashboard"
                )
            }
            .padding(.horizontal, 48)
            .padding(.top, 16)
            
            Spacer()
        }
        .padding()
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
        .background(Color(nsColor: .controlBackgroundColor))
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
