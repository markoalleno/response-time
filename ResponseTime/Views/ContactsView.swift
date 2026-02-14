import SwiftUI
import SwiftData
import Charts

// MARK: - Contacts Analytics View

struct ContactsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    @State private var searchText = ""
    @State private var sortBy: SortOption = .responseTime
    @State private var selectedContact: iMessageConnector.ContactStats?
    @State private var showGroups = false
    
    // Real data from iMessage
    @State private var contacts: [iMessageConnector.ContactStats] = []
    @State private var conversations: [iMessageConnector.ConversationData] = []
    @State private var overallStats: iMessageConnector.OverallStats = .empty
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private let connector = iMessageConnector()
    
    enum SortOption: String, CaseIterable {
        case responseTime = "Response Time"
        case messageCount = "Message Count"
        case name = "Name"
        case recent = "Most Recent"
    }
    
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
            LazyVStack(spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Contact Analytics")
                            .font(.title2.bold())
                        
                        Spacer()
                        
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Button {
                                Task { await loadData() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Text("Real response times from your iMessage history")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if let error = errorMessage {
                    errorView(error)
                } else {
                    // Search and sort
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search contacts...", text: $searchText)
                                .textFieldStyle(.plain)
                        }
                        .padding(8)
                        .background(cardBackgroundColor)
                        .cornerRadius(8)
                        
                        Picker("Sort", selection: $sortBy) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        #if os(macOS)
                        .pickerStyle(.menu)
                        #endif
                        .frame(width: 150)
                    }
                    
                    // Summary stats
                    summaryCards
                    
                    // Fastest & slowest responders
                    if !contacts.isEmpty {
                        topRespondersSection
                    }
                    
                    // Toggle between Contacts and Groups
                    Picker("View", selection: $showGroups) {
                        Text("Individuals (\(filteredContacts.count))").tag(false)
                        Text("Groups (\(filteredGroups.count))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 8)
                    
                    // Contact/Group list
                    if showGroups {
                        if filteredGroups.isEmpty {
                            emptyState(message: "No group chats found")
                        } else {
                            groupList
                        }
                    } else {
                        if filteredContacts.isEmpty {
                            emptyState(message: isLoading ? "Loading..." : "No contacts found")
                        } else {
                            contactList
                        }
                    }
                }
            }
            .padding(viewPadding)
        }
        .background(backgroundColor)
        .task {
            await loadData()
        }
        .sheet(item: $selectedContact) { contact in
            ContactDetailSheet(contact: contact, connector: connector, resolvedName: contactNames[contact.identifier])
        }
    }
    
    private var viewPadding: CGFloat {
        #if os(macOS)
        return 24
        #else
        return 16
        #endif
    }
    
    @State private var contactNames: [String: String] = [:]
    
    private func loadData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let contactsTask = connector.fetchContactStats(days: 30)
            async let conversationsTask = connector.fetchAllConversations(days: 30)
            async let statsTask = connector.getOverallStats(days: 30)
            
            let (fetchedContacts, fetchedConversations, fetchedStats) = try await (
                contactsTask,
                conversationsTask,
                statsTask
            )
            
            contacts = fetchedContacts
            conversations = fetchedConversations
            overallStats = fetchedStats
            
            // Resolve contact names
            let identifiers = fetchedContacts.map(\.identifier)
            let resolver = ContactResolver.shared
            _ = await resolver.requestAccessAndLoad()
            contactNames = await resolver.resolveAll(identifiers)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Unable to load iMessage data")
                .font(.headline)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if message.contains("Full Disk Access") {
                Button("Open System Settings") {
                    #if os(macOS)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    #endif
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private var summaryCards: some View {
        #if os(macOS)
        HStack(spacing: 16) {
            summaryCardContent
        }
        #else
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            summaryCardContent
        }
        #endif
    }
    
    @ViewBuilder
    private var summaryCardContent: some View {
        ContactSummaryCard(
            icon: "person.2.fill",
            color: .blue,
            title: "Total Contacts",
            value: "\(overallStats.totalContacts)"
        )
        
        ContactSummaryCard(
            icon: "clock.fill",
            color: .green,
            title: "Median Response",
            value: overallStats.medianResponseTime.map { formatDuration($0) } ?? "--"
        )
        
        ContactSummaryCard(
            icon: "arrow.up.arrow.down",
            color: .orange,
            title: "Total Responses",
            value: "\(overallStats.totalResponses)"
        )
        
        ContactSummaryCard(
            icon: "exclamationmark.bubble.fill",
            color: .red,
            title: "Pending",
            value: "\(overallStats.pendingResponses)"
        )
    }
    
    private var topRespondersSection: some View {
        let withResponse = contacts.filter { $0.medianResponseTime != nil && $0.responseCount >= 2 }
        let fastest = withResponse.sorted { ($0.medianResponseTime ?? .infinity) < ($1.medianResponseTime ?? .infinity) }.prefix(3)
        let slowest = withResponse.sorted { ($0.medianResponseTime ?? 0) > ($1.medianResponseTime ?? 0) }.prefix(3)
        
        return Group {
            if !fastest.isEmpty {
                #if os(macOS)
                HStack(spacing: 16) {
                    miniRankCard(title: "⚡ Fastest", contacts: Array(fastest), color: .green)
                    miniRankCard(title: "🐢 Slowest", contacts: Array(slowest), color: .orange)
                }
                #else
                VStack(spacing: 12) {
                    miniRankCard(title: "⚡ Fastest", contacts: Array(fastest), color: .green)
                    miniRankCard(title: "🐢 Slowest", contacts: Array(slowest), color: .orange)
                }
                #endif
            }
        }
    }
    
    private func miniRankCard(title: String, contacts: [iMessageConnector.ContactStats], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
            
            ForEach(Array(contacts.enumerated()), id: \.element.id) { idx, contact in
                HStack(spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    
                    Text(contactNames[contact.identifier] ?? contact.displayName ?? contact.identifier)
                        .font(.caption)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(contact.medianResponseTime.map { formatDuration($0) } ?? "--")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(color)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private func emptyState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(message)
                .font(.headline)
            
            Text("Check that Full Disk Access is enabled for this app")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private var contactList: some View {
        LazyVStack(spacing: 8) {
            ForEach(sortedContacts) { contact in
                RealContactRow(contact: contact, resolvedName: contactNames[contact.identifier])
                    .onTapGesture {
                        selectedContact = contact
                    }
            }
        }
    }
    
    private var groupList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredGroups) { group in
                GroupRow(conversation: group)
            }
        }
    }
    
    private var filteredContacts: [iMessageConnector.ContactStats] {
        var result = contacts
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.identifier.localizedCaseInsensitiveContains(searchText) ||
                ($0.displayName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (contactNames[$0.identifier]?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        return result
    }
    
    private var sortedContacts: [iMessageConnector.ContactStats] {
        var result = filteredContacts
        
        switch sortBy {
        case .responseTime:
            result.sort { ($0.medianResponseTime ?? .infinity) < ($1.medianResponseTime ?? .infinity) }
        case .messageCount:
            result.sort { $0.totalMessages > $1.totalMessages }
        case .name:
            result.sort { $0.identifier < $1.identifier }
        case .recent:
            result.sort { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
        }
        
        return result
    }
    
    private var filteredGroups: [iMessageConnector.ConversationData] {
        var result = conversations.filter { $0.isGroupChat }
        
        if !searchText.isEmpty {
            result = result.filter {
                ($0.displayName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.chatIdentifier.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result.sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
    }
}

// MARK: - Contact Summary Card

struct ContactSummaryCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .lineLimit(1)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Real Contact Row (using real data)

struct RealContactRow: View {
    let contact: iMessageConnector.ContactStats
    var resolvedName: String? = nil
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(serviceColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                Text(initials)
                    .font(.headline)
                    .foregroundColor(serviceColor)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    // Service badge
                    Text(contact.service == "SMS" ? "SMS" : "iMessage")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(serviceColor.opacity(0.2))
                        .foregroundColor(serviceColor)
                        .cornerRadius(4)
                }
                
                HStack(spacing: 8) {
                    Label("\(contact.totalMessages)", systemImage: "message.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if contact.pendingCount > 0 {
                        Label("Pending", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Response time
            VStack(alignment: .trailing, spacing: 4) {
                if let median = contact.medianResponseTime {
                    Text(formatDuration(median))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(responseColor(for: median))
                } else {
                    Text("--")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Text("\(contact.responseCount) responses")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private var displayName: String {
        resolvedName ?? contact.displayName ?? formatPhoneOrEmail(contact.identifier)
    }
    
    private var initials: String {
        let name = displayName
        let parts = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
    
    private var serviceColor: Color {
        contact.service == "SMS" ? .green : .blue
    }
    
    private func formatPhoneOrEmail(_ identifier: String) -> String {
        if identifier.hasPrefix("+") {
            let digits = identifier.filter { $0.isNumber }
            guard digits.count == 11, digits.hasPrefix("1") else {
                return identifier
            }
            let area = digits.dropFirst().prefix(3)
            let prefix = digits.dropFirst(4).prefix(3)
            let line = digits.dropFirst(7)
            return "(\(area)) \(prefix)-\(line)"
        }
        return identifier
    }
    
    private func responseColor(for seconds: TimeInterval) -> Color {
        if seconds < 1800 { return .green }       // < 30 min
        if seconds < 7200 { return .yellow }      // < 2 hours
        if seconds < 86400 { return .orange }     // < 1 day
        return .red
    }
}

// MARK: - Group Row

struct GroupRow: View {
    let conversation: iMessageConnector.ConversationData
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Group avatar
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.3.fill")
                    .font(.headline)
                    .foregroundColor(.purple)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.displayName ?? "Group Chat")
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label("\(conversation.participantCount)", systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("\(conversation.messageCount)", systemImage: "message.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Response time
            VStack(alignment: .trailing, spacing: 4) {
                if let median = conversation.medianResponseTime {
                    Text(formatDuration(median))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(responseColor(for: median))
                } else {
                    Text("--")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                if conversation.pendingResponse {
                    Label("Pending", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("\(conversation.responseCount) responses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private func responseColor(for seconds: TimeInterval) -> Color {
        if seconds < 1800 { return .green }
        if seconds < 7200 { return .yellow }
        if seconds < 86400 { return .orange }
        return .red
    }
}

// MARK: - Contact Detail Sheet

struct ContactDetailSheet: View {
    let contact: iMessageConnector.ContactStats
    let connector: iMessageConnector
    var resolvedName: String? = nil
    
    @Environment(\.dismiss) private var dismiss
    @State private var responseTimes: [ResponseTimeData] = []
    @State private var isLoading = true
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(serviceColor.opacity(0.2))
                                .frame(width: 80, height: 80)
                            Text(initials)
                                .font(.largeTitle)
                                .foregroundColor(serviceColor)
                        }
                        
                        Text(displayName)
                            .font(.title2.bold())
                        
                        Text(contact.identifier)
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Text(contact.service)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(serviceColor.opacity(0.2))
                            .foregroundColor(serviceColor)
                            .cornerRadius(6)
                    }
                    
                    // Stats
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        StatBox(
                            title: "Median Response",
                            value: contact.medianResponseTime.map { formatDuration($0) } ?? "--",
                            color: .blue
                        )
                        StatBox(
                            title: "Messages",
                            value: "\(contact.totalMessages)",
                            color: .purple
                        )
                        StatBox(
                            title: "Best",
                            value: (responseTimes.map(\.latencySeconds).min()).map { formatDuration($0) } ?? "--",
                            color: .green
                        )
                        StatBox(
                            title: "Worst",
                            value: (responseTimes.map(\.latencySeconds).max()).map { formatDuration($0) } ?? "--",
                            color: .red
                        )
                    }
                    
                    // Response time trend
                    if !responseTimes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Response Time Trend")
                                .font(.headline)
                            
                            SparklineChart(
                                values: responseTimes.suffix(20).reversed().map { $0.latencySeconds / 60 },
                                color: .accentColor
                            )
                            .frame(height: 60)
                        }
                        .padding()
                        .background(cardBackgroundColor)
                        .cornerRadius(12)
                    }
                    
                    // Response history
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Responses")
                            .font(.headline)
                        
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if responseTimes.isEmpty {
                            Text("No response data available")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            ForEach(responseTimes.prefix(10), id: \.outboundTime) { response in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Received")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(response.inboundTime, style: .relative)
                                            .font(.subheadline)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing) {
                                        Text("Response Time")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(formatDuration(response.latencySeconds))
                                            .font(.system(.subheadline, design: .monospaced))
                                            .foregroundColor(responseColor(for: response.latencySeconds))
                                    }
                                }
                                .padding(.vertical, 8)
                                
                                Divider()
                            }
                        }
                    }
                    .padding()
                    .background(cardBackgroundColor)
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Contact Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadResponseTimes()
            }
        }
        #if os(macOS)
        .frame(width: 450, height: 600)
        #endif
    }
    
    private func loadResponseTimes() async {
        isLoading = true
        do {
            let allResponses = try await connector.getRecentResponseTimes(days: 30)
            responseTimes = allResponses.filter { $0.participant == contact.identifier }
                .sorted { $0.outboundTime > $1.outboundTime }
        } catch {
            // Silently fail
        }
        isLoading = false
    }
    
    private var displayName: String {
        resolvedName ?? contact.displayName ?? contact.identifier
    }
    
    private var initials: String {
        let name = displayName
        let parts = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
    
    private var serviceColor: Color {
        contact.service == "SMS" ? .green : .blue
    }
    
    private func responseColor(for seconds: TimeInterval) -> Color {
        if seconds < 1800 { return .green }
        if seconds < 7200 { return .yellow }
        if seconds < 86400 { return .orange }
        return .red
    }
}

// MARK: - Stat Box

struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Legacy Contact Row (keeping for SwiftData compatibility)

struct ContactRow: View {
    let contact: Participant
    
    private var medianResponse: String { formatDuration(Double.random(in: 1800...7200)) }
    private var messageCount: Int { Int.random(in: 5...50) }
    private var trend: Double { Double.random(in: -20...20) }
    
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
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                Text(initials)
                    .font(.headline)
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName ?? contact.email)
                    .font(.headline)
                    .lineLimit(1)
                
                if contact.displayName != nil {
                    Text(contact.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(medianResponse)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(responseColor)
                
                HStack(spacing: 4) {
                    Image(systemName: trend < 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.caption2)
                    Text("\(abs(Int(trend)))%")
                        .font(.caption)
                }
                .foregroundColor(trend < 0 ? .green : .red)
            }
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
    }
    
    private var initials: String {
        let name = contact.displayName ?? contact.email
        let parts = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
    
    private var responseColor: Color {
        let minutes = Double.random(in: 30...120)
        if minutes < 60 { return .green }
        if minutes < 120 { return .yellow }
        return .red
    }
}

#Preview {
    ContactsView()
        .environment(AppState())
        .modelContainer(for: Participant.self)
}
