import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \ResponseGoal.sortOrder) private var goals: [ResponseGoal]
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
                        GoalCard(goal: goal, responseWindows: responseWindows) {
                            deleteGoal(goal)
                        }
                        .draggable(goal.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedId = items.first,
                                  let draggedUUID = UUID(uuidString: draggedId),
                                  let fromIndex = goals.firstIndex(where: { $0.id == draggedUUID }),
                                  let toIndex = goals.firstIndex(where: { $0.id == goal.id }),
                                  fromIndex != toIndex else { return false }
                            reorderGoals(from: fromIndex, to: toIndex)
                            return true
                        }
                    }
                }
                
                // Streak summary
                if !goals.isEmpty {
                    streakSummaryCard
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
    
    @Query(sort: \ResponseWindow.computedAt, order: .reverse)
    private var responseWindows: [ResponseWindow]
    
    private var overallProgressCard: some View {
        let valid = responseWindows.filter(\.isValidForAnalytics)
        // Use the strictest goal target, or default to 1 hour
        let target = goals.filter(\.isEnabled).map(\.targetLatencySeconds).min() ?? 3600
        let withinTarget = valid.filter { $0.latencySeconds <= target }
        let close = valid.filter { $0.latencySeconds > target && $0.latencySeconds <= target * 1.5 }
        let missed = valid.filter { $0.latencySeconds > target * 1.5 }
        let progress = valid.isEmpty ? 0.0 : Double(withinTarget.count) / Double(valid.count)
        let closePercent = valid.isEmpty ? 0 : Int(Double(close.count) / Double(valid.count) * 100)
        let missedPercent = valid.isEmpty ? 0 : Int(Double(missed.count) / Double(valid.count) * 100)
        let progressPercent = Int(progress * 100)
        
        return VStack(spacing: 16) {
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
                    Text(valid.isEmpty ? "--" : "\(progressPercent)%")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(progress >= 0.8 ? .green : progress >= 0.6 ? .yellow : .red)
                    Text(valid.isEmpty ? "no data yet" : "responses within target")
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
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 12)
            
            // Legend
            HStack(spacing: 16) {
                LegendItem(color: .green, label: "Within target (\(progressPercent)%)")
                LegendItem(color: .yellow, label: "Close (\(closePercent)%)")
                LegendItem(color: .red, label: "Missed (\(missedPercent)%)")
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
            platform: .imessage,
            target: "30 minutes",
            description: "Quick reply to personal messages"
        ) {
            addSuggestedGoal(.imessage, 1800)
        }
        
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
        
        SuggestedGoalCard(
            platform: nil,
            target: "2 hours",
            description: "Reasonable target across all platforms"
        ) {
            addSuggestedGoal(nil, 7200)
        }
    }
    
    private func addSuggestedGoal(_ platform: Platform?, _ seconds: TimeInterval) {
        let goal = ResponseGoal(
            platform: platform,
            targetLatencySeconds: seconds
        )
        modelContext.insert(goal)
        try? modelContext.save()
    }
    
    private var streakSummaryCard: some View {
        let streakData = computeStreaks()
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("Streaks")
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(streakData.current)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(streakData.current > 0 ? .orange : .secondary)
                    Text("Current streak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 4) {
                    Text("\(streakData.longest)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                    Text("Best streak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Last 7 days visualization
                VStack(spacing: 4) {
                    HStack(spacing: 3) {
                        ForEach(streakData.last7Days, id: \.offset) { day in
                            Circle()
                                .fill(day.metGoal ? Color.green : day.hadData ? Color.red : Color.secondary.opacity(0.2))
                                .frame(width: 14, height: 14)
                        }
                    }
                    Text("Last 7 days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private struct StreakData {
        var current: Int
        var longest: Int
        var last7Days: [(offset: Int, metGoal: Bool, hadData: Bool)]
    }
    
    private func computeStreaks() -> StreakData {
        let calendar = Calendar.current
        let valid = responseWindows.filter(\.isValidForAnalytics)
        let target = goals.filter(\.isEnabled).map(\.targetLatencySeconds).min() ?? 3600
        
        // Group windows by day
        var dayResults: [Date: Bool] = [:]
        var dayHasData: Set<Date> = []
        
        for window in valid {
            guard let t = window.inboundEvent?.timestamp else { continue }
            let day = calendar.startOfDay(for: t)
            dayHasData.insert(day)
            let currentResult = dayResults[day] ?? true
            dayResults[day] = currentResult && (window.latencySeconds <= target)
        }
        
        // Compute current streak (consecutive days meeting goal, ending today or yesterday)
        var current = 0
        var checkDate = calendar.startOfDay(for: Date())
        // Allow starting from yesterday if today has no data
        if dayResults[checkDate] == nil {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }
        while let met = dayResults[checkDate], met {
            current += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }
        
        // Compute longest streak
        let sortedDays = dayResults.keys.sorted()
        var longest = 0
        var streak = 0
        for day in sortedDays {
            if dayResults[day] == true {
                streak += 1
                longest = max(longest, streak)
            } else {
                streak = 0
            }
        }
        
        // Last 7 days
        let today = calendar.startOfDay(for: Date())
        let last7 = (0..<7).reversed().map { offset -> (offset: Int, metGoal: Bool, hadData: Bool) in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let hadData = dayHasData.contains(day)
            let metGoal = dayResults[day] ?? false
            return (offset: offset, metGoal: metGoal, hadData: hadData)
        }
        
        return StreakData(current: current, longest: longest, last7Days: last7)
    }
    
    private func reorderGoals(from: Int, to: Int) {
        var ordered = goals.map { $0 }
        let item = ordered.remove(at: from)
        ordered.insert(item, at: to)
        for (index, goal) in ordered.enumerated() {
            goal.sortOrder = index
        }
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
    let responseWindows: [ResponseWindow]
    let onDelete: () -> Void
    
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    
    private var progress: Double {
        var valid = responseWindows.filter(\.isValidForAnalytics)
        if let platform = goal.platform {
            valid = valid.filter { $0.inboundEvent?.conversation?.sourceAccount?.platform == platform }
        }
        guard !valid.isEmpty else { return 0 }
        let withinTarget = valid.filter { $0.latencySeconds <= goal.targetLatencySeconds }
        return Double(withinTarget.count) / Double(valid.count)
    }
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
    let platform: Platform?
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
                Image(systemName: platform?.icon ?? "target")
                    .foregroundColor(platform?.color ?? .accentColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(platform?.displayName ?? "All Platforms"): \(target)")
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
