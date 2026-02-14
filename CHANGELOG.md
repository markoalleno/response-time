# Changelog

## v1.0.0 (2025-02-14) — Initial Release

### Dashboard
- Real-time response metrics with trend indicators
- Response Score (A+ to F grade: speed, consistency, coverage)
- Response Velocity (responses/day with week-over-week comparison)
- Percentile card (10th/50th/90th)
- Work vs Off-Hours comparison
- Recent Responses list (last 5)
- Goal progress ring
- Platform breakdown
- Last synced indicator

### Weekly Digest
- Week navigation with summary metrics
- Response Score with comparison
- Highlights card (fastest, busiest day, peak hour)
- Goal streaks with flame icons
- Day-by-day breakdown chart
- Top contacts
- Copy report to clipboard

### Analytics (9 chart types)
- Trend, Compare, Weekly, Heatmap, Hourly, Distribution, By Platform, By Contact, Activity Graph
- Contact filter text field
- Stats grid with key metrics

### Contacts
- Per-contact analytics with fastest/slowest rankings
- iMessage/SMS service filter
- Contact detail with distribution mini-chart, sparkline, response history
- Search and VoiceOver accessibility

### Goals & Streaks
- Create/edit/delete response time goals
- Drag-to-reorder priority
- Current and longest streak tracking (auto-updated on sync)
- 7-day dot visualization
- Suggested goals
- Streak record notifications

### Pending Responses
- Archive and snooze (1h/4h/24h)
- Quick reply button (opens Messages)
- Auto-cleanup expired snoozes

### Smart Insights
- Day/hour patterns, speed tiers, consistency analysis
- Working hours vs off-hours comparison
- Week-over-week trends

### Siri & Shortcuts
- Get Response Time, Goal Progress, Pending Responses, Sync Now

### Widget
- Small/Medium/Large with real iMessage data
- Grade badge, pending count, goal progress

### Menu Bar
- Median, grade, trend %, pending count
- Copy stats to clipboard

### Notifications
- Threshold alerts, daily summary, pending reminders
- Streak record notifications
- Quiet hours (10 PM - 7 AM)
- Configurable quiet hours in settings

### Export
- CSV, JSON, Markdown summary

### Privacy
- 100% local processing, no cloud, metadata only
- Full Disk Access permission flow
- One-click data deletion

### Technical
- Swift 6 with strict concurrency
- SwiftUI + SwiftData + Swift Charts
- App Intents + WidgetKit
- 41 unit tests
- Auto-sync timer (30 min)
- Keyboard shortcuts (⌘1-5, ⌘R, ⌘,)
- Onboarding flow with permission checks
