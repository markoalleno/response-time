# Sync Fix - Feb 14, 2026

## Issue
App showed "No data yet" after sync completed. Investigation revealed sync was hanging during the very first database fetch operation.

## Root Cause
**SwiftData Background Context + Predicate Hang**

When using a `FetchDescriptor` with a `#Predicate` on a background `ModelContext`, the fetch operation would hang indefinitely. This appeared to be specific to predicates comparing enum values:

```swift
let targetPlatform = Platform.imessage
let descriptor = FetchDescriptor<SourceAccount>(
    predicate: #Predicate { $0.platform == targetPlatform }
)
let results = try modelContext.fetch(descriptor)  // ← HANGS FOREVER
```

This may be a Swift 6.0 concurrency issue or SwiftData bug with background contexts.

## Fix
Changed `getOrCreateSourceAccount()` to fetch all records without a predicate, then filter manually:

```swift
private func getOrCreateSourceAccount(modelContext: ModelContext) throws -> SourceAccount {
    // Fetch all source accounts without predicate (workaround for background context hang)
    let descriptor = FetchDescriptor<SourceAccount>()
    let allAccounts = try modelContext.fetch(descriptor)
    
    // Filter for iMessage account manually
    if let existing = allAccounts.first(where: { $0.platform == .imessage }) {
        return existing
    }
    
    // Create new account if not found
    let account = SourceAccount(platform: .imessage, displayName: "iMessage", isEnabled: true)
    modelContext.insert(account)
    return account
}
```

## Results
✅ Sync completes successfully  
✅ 797 ResponseWindow records created from 10,000 messages
✅ 99 conversations processed
✅ No more hanging

## Testing
```bash
cd /Users/mark/response-time
xcodegen generate
xcodebuild -scheme ResponseTime-macOS -destination 'platform=macOS' build

# Launch and trigger sync with Cmd+R
# Check logs:
tail -f /tmp/rt-sync-debug.log
```

## Database Location
SwiftData store is in Group Container (not regular app container):
```
/Users/mark/Library/Group Containers/FG42YJ5PSB.com.allens.responsetime/Library/Application Support/default.store
```

## Debugging Added
- Created `DebugLog.swift` with `debugLog()` function that writes to both console and `/tmp/rt-sync-debug.log`
- Added comprehensive logging throughout sync pipeline
- Added logging to ModelContainer creation in `ResponseTimeApp.swift`

## Performance Optimization (Added after initial fix)
Large conversations (1000+ messages) were taking 30-60 seconds to process due to individual database queries checking for duplicate MessageEvents.

**Optimization:** Batch fetch all existing MessageEvents at the start of each conversation, then check against an in-memory Set:

```swift
// Batch fetch existing events for this conversation (optimization)
let eventIds = Set(sortedEvents.map(\.id))
let existingDescriptor = FetchDescriptor<MessageEvent>()
let allExistingEvents = (try? backgroundContext.fetch(existingDescriptor)) ?? []
let existingIds = Set(allExistingEvents.filter { eventIds.contains($0.id) }.map(\.id))

for eventData in sortedEvents {
    // Check against pre-fetched set (O(1) lookup vs O(n) DB query)
    if existingIds.contains(eventData.id) {
        totalEventsSkipped += 1
        continue
    }
    // ... create MessageEvent
}
```

This reduces N database queries per conversation to just 1, dramatically improving performance.

## Notes
- Other `getOrCreate` methods (`getOrCreateParticipant`, `getOrCreateConversation`) also use predicates but didn't hang - may be specific to enum comparisons
- Consider filing a bug report with Apple about SwiftData background context predicate hangs
- Performance bottleneck: duplicate checking. Solved with batch fetch + Set lookup.
