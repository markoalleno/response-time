import SwiftUI
import SwiftData

struct PlatformsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    @Query private var accounts: [SourceAccount]
    
    @State private var showingAddPlatform = false
    @State private var selectedPlatformToAdd: Platform?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connected Platforms")
                        .font(.title2.bold())
                    Text("Connect your communication platforms to track response times")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Connected accounts
                if !accounts.isEmpty {
                    ForEach(accounts) { account in
                        ConnectedAccountCard(account: account, onDelete: {
                            deleteAccount(account)
                        })
                    }
                }
                
                // Add new platforms
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add Platform")
                        .font(.headline)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(Platform.allCases.filter { platform in
                            !accounts.contains { $0.platform == platform }
                        }) { platform in
                            PlatformAddCard(platform: platform) {
                                selectedPlatformToAdd = platform
                                showingAddPlatform = true
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingAddPlatform) {
            if let platform = selectedPlatformToAdd {
                AddPlatformSheet(platform: platform) { account in
                    modelContext.insert(account)
                    try? modelContext.save()
                    showingAddPlatform = false
                }
            }
        }
    }
    
    private func deleteAccount(_ account: SourceAccount) {
        modelContext.delete(account)
        try? modelContext.save()
    }
}

// MARK: - Connected Account Card

struct ConnectedAccountCard: View {
    let account: SourceAccount
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirm = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Platform icon
            ZStack {
                Circle()
                    .fill(account.platform.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: account.platform.icon)
                    .font(.title2)
                    .foregroundColor(account.platform.color)
            }
            
            // Account info
            VStack(alignment: .leading, spacing: 4) {
                Text(account.platform.displayName)
                    .font(.headline)
                Text(account.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let email = account.email {
                    Text(email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Status and actions
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(account.isEnabled ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(account.isEnabled ? "Active" : "Paused")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 8) {
                    if let syncDate = account.syncCheckpoint {
                        Text("Synced \(syncDate, style: .relative)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        showingDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .confirmationDialog(
            "Disconnect \(account.platform.displayName)?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect and Delete Data", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all response time data from this account.")
        }
    }
}

// MARK: - Platform Add Card

struct PlatformAddCard: View {
    let platform: Platform
    let onAdd: () -> Void
    
    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(platform.color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: platform.icon)
                        .foregroundColor(platform.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(platformDescription(platform))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func platformDescription(_ platform: Platform) -> String {
        switch platform {
        case .gmail: return "Track email response times"
        case .outlook: return "Microsoft 365 email tracking"
        case .slack: return "DMs and mentions"
        case .imessage: return "Messages (requires permissions)"
        }
    }
}

// MARK: - Add Platform Sheet

struct AddPlatformSheet: View {
    let platform: Platform
    let onComplete: (SourceAccount) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthenticating = false
    @State private var error: String?
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(platform.color.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: platform.icon)
                        .font(.largeTitle)
                        .foregroundColor(platform.color)
                }
                
                Text("Connect \(platform.displayName)")
                    .font(.title2.bold())
                
                Text(permissionDescription)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Permissions list
            VStack(alignment: .leading, spacing: 12) {
                Text("We will request:")
                    .font(.headline)
                
                ForEach(permissions, id: \.self) { permission in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(permission)
                    }
                }
                
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("We never read message content")
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Spacer()
            
            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button {
                    startAuth()
                } label: {
                    if isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Connect \(platform.displayName)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
            }
        }
        .padding(24)
        .frame(width: 450, height: 500)
    }
    
    private var permissionDescription: String {
        switch platform {
        case .gmail:
            return "Response Time will analyze your email timestamps to calculate response times. No message content is accessed."
        case .outlook:
            return "Connect your Microsoft 365 account to track email response metrics."
        case .slack:
            return "Track response times for direct messages and mentions."
        case .imessage:
            return "Analyze iMessage response patterns. Requires Full Disk Access."
        }
    }
    
    private var permissions: [String] {
        switch platform {
        case .gmail:
            return ["Read email metadata (timestamps, participants)", "Access thread information"]
        case .outlook:
            return ["Read mail metadata", "Offline access for background sync"]
        case .slack:
            return ["View DM timestamps", "View mentions"]
        case .imessage:
            return ["Read message timestamps", "Read conversation participants"]
        }
    }
    
    private func startAuth() {
        isAuthenticating = true
        
        // Simulate OAuth flow
        Task {
            try? await Task.sleep(for: .seconds(2))
            
            // Create account (in real app, this would be after OAuth)
            let account = SourceAccount(
                platform: platform,
                displayName: "Demo Account",
                email: "demo@example.com"
            )
            
            await MainActor.run {
                onComplete(account)
            }
        }
    }
}

#Preview {
    PlatformsView()
        .environment(AppState())
        .modelContainer(for: SourceAccount.self)
}
