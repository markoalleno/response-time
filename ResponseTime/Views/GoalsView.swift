import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    @Query private var goals: [ResponseGoal]
    @Query private var accounts: [SourceAccount]
    
    @State private var showingAddGoal = false
    
    private var backgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Response Goals")
                            .font(.title2.bold())
                        Text("Set targets and track your progress")
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        showingAddGoal = true
                    } label: {
                        Label("Add Goal", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                // Overall progress
                overallProgressCard
                
                // Individual goals
                if goals.isEmpty {
                    emptyState
                } else {
                    ForEach(goals) { goal in
                        GoalCard(goal: goal) {
                            deleteGoal(goal)
                        }
                    }
                }
                
                // Suggested goals
                if goals.count < 3 {
                    suggestedGoalsSection
                }
            }
            .padding(viewPadding)
        }
        .background(backgroundColor)
        .sheet(isPresented: $showingAddGoal) {
            AddGoalSheet { goal in
                modelContext.insert(goal)
                try? modelContext.save()
            }
        }
    }
    
    private var viewPadding: CGFloat {
        #if os(macOS)
        return 24
        #else
        return 16
        #endif
    }
    
    private var overallProgressCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Overall Progress")
                        .font(.headline)
                    Text("This week")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("78%")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                    Text("responses within target")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(progressGradient)
                        .frame(width: geo.size.width * 0.78)
                }
            }
            .frame(height: 12)
            
            // Legend
            HStack(spacing: 16) {
                LegendItem(color: .green, label: "Within target (78%)")
                LegendItem(color: .yellow, label: "Close (12%)")
                LegendItem(color: .red, label: "Missed (10%)")
            }
            .font(.caption)
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .green.opacity(0.8)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No goals set")
                .font(.headline)
            
            Text("Create goals to track your response time improvements")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingAddGoal = true
            } label: {
                Label("Create First Goal", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private var suggestedGoalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested Goals")
                .font(.headline)
            
            #if os(macOS)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                suggestedGoalCards
            }
            #else
            LazyVStack(spacing: 12) {
                suggestedGoalCards
            }
            #endif
        }
    }
    
    @ViewBuilder
    private var suggestedGoalCards: some View {
        SuggestedGoalCard(
            platform: .gmail,
            target: "1 hour",
            description: "Industry average for email"
        ) {
            addSuggestedGoal(.gmail, 3600)
        }
        
        SuggestedGoalCard(
            platform: .slack,
            target: "15 minutes",
            description: "Quick response for DMs"
        ) {
            addSuggestedGoal(.slack, 900)
        }
    }
    
    private func addSuggestedGoal(_ platform: Platform, _ seconds: TimeInterval) {
        let goal = ResponseGoal(
            platform: platform,
            targetLatencySeconds: seconds
        )
        modelContext.insert(goal)
        try? modelContext.save()
    }
    
    private func deleteGoal(_ goal: ResponseGoal) {
        modelContext.delete(goal)
        try? modelContext.save()
    }
}

// MARK: - Goal Card

struct GoalCard: View {
    let goal: ResponseGoal
    let onDelete: () -> Void
    
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    
    // Simulated progress (would come from actual analytics)
    private var progress: Double { Double.random(in: 0.5...0.95) }
    private var progressColor: Color {
        if progress >= 0.8 { return .green }
        if progress >= 0.6 { return .yellow }
        return .red
    }
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Platform icon
            if let platform = goal.platform {
                ZStack {
                    Circle()
                        .fill(platform.color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: platform.icon)
                        .font(.title2)
                        .foregroundColor(platform.color)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "target")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Goal info
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.platform?.displayName ?? "All Platforms")
                    .font(.headline)
                
                HStack {
                    Text("Target:")
                    Text(goal.formattedTarget)
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Progress
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(progress * 100))%")
                    .font(.title2.bold())
                    .foregroundColor(progressColor)
                
                Text("on target")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Actions
            Menu {
                Button {
                    showingEdit = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .frame(width: 30)
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
        .confirmationDialog(
            "Delete goal?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Suggested Goal Card

struct SuggestedGoalCard: View {
    let platform: Platform
    let target: String
    let description: String
    let onAdd: () -> Void
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 12) {
                Image(systemName: platform.icon)
                    .foregroundColor(platform.color)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(platform.displayName): \(target)")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(cardBackgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legend Item

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Add Goal Sheet

struct AddGoalSheet: View {
    let onSave: (ResponseGoal) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPlatform: Platform?
    @State private var targetHours: Int = 1
    @State private var targetMinutes: Int = 0
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Create Goal")
                    .font(.title2.bold())
                
                // Platform picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Platform")
                        .font(.headline)
                    
                    Picker("Platform", selection: $selectedPlatform) {
                        Text("All Platforms").tag(nil as Platform?)
                        ForEach(Platform.allCases) { platform in
                            Label(platform.displayName, systemImage: platform.icon)
                                .tag(platform as Platform?)
                        }
                    }
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #endif
                }
                
                // Target time
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target Response Time")
                        .font(.headline)
                    
                    HStack {
                        Picker("Hours", selection: $targetHours) {
                            ForEach(0..<24) { hour in
                                Text("\(hour)h").tag(hour)
                            }
                        }
                        .frame(width: 80)
                        
                        Picker("Minutes", selection: $targetMinutes) {
                            ForEach([0, 15, 30, 45], id: \.self) { min in
                                Text("\(min)m").tag(min)
                            }
                        }
                        .frame(width: 80)
                    }
                }
                
                // Preview
                HStack {
                    Text("Goal:")
                        .foregroundColor(.secondary)
                    Text("Respond within \(targetHours)h \(targetMinutes)m")
                        .fontWeight(.medium)
                }
                .padding()
                .background(cardBackgroundColor)
                .cornerRadius(8)
                
                Spacer()
                
                // Actions
                #if os(macOS)
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                    
                    Spacer()
                    
                    createButton
                }
                #else
                createButton
                    .frame(maxWidth: .infinity)
                #endif
            }
            .padding(24)
            #if os(macOS)
            .frame(width: 400, height: 400)
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
    }
    
    private var createButton: some View {
        Button("Create Goal") {
            let seconds = TimeInterval(targetHours * 3600 + targetMinutes * 60)
            let goal = ResponseGoal(
                platform: selectedPlatform,
                targetLatencySeconds: seconds
            )
            onSave(goal)
            dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(targetHours == 0 && targetMinutes == 0)
        #if os(iOS)
        .controlSize(.large)
        #endif
    }
}

#Preview {
    GoalsView()
        .environment(AppState())
        .modelContainer(for: ResponseGoal.self)
}
