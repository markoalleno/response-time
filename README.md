# Response Time

A privacy-first macOS app that analyzes your personal response times across messaging platforms.

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Tests](https://img.shields.io/badge/tests-36%20passing-brightgreen)

## Features

### 📊 Dashboard
- Real-time response time metrics with trend indicators
- **Response Score** — composite A+ to F grade (speed, consistency, coverage)
- **Response Velocity** — responses/day with week-over-week comparison
- Goal progress ring visualization
- Platform breakdown by median response time
- Pending responses with archive/snooze/quick reply
- Last synced indicator

### 📅 Weekly Digest
- Week-by-week navigation with summary metrics
- Response Score with week-over-week comparison
- Daily breakdown chart
- Top contacts for the week
- Highlights section (fastest response, busiest day, peak hour)
- Day-by-day horizontal bar visualization

### 📈 Analytics (7 chart types)
- **Trend** — Response time over time with area fill
- **Compare** — Current vs previous period overlay
- **Weekly** — Day-of-week breakdown (weekday vs weekend)
- **Heatmap** — 7×24 day/hour grid with intensity-based colors
- **Hourly** — Hour-of-day response patterns
- **Distribution** — Response time buckets (<30m, 30m-1h, etc.)
- **By Platform** — Horizontal bar comparison

### 🧠 Smart Insights
- "You respond faster on Tuesdays"
- Peak hour identification
- Working hours vs off-hours comparison
- Speed tier classification (Speed Demon / Taking Your Time)
- Week-over-week trend (Improving! / Slowing Down)
- Consistency analysis (tight cluster vs wide variance)

### 🎯 Goals & Streaks
- Create response time goals per platform or globally
- Drag-to-reorder goal priority
- Current streak and longest streak tracking
- 7-day dot visualization
- Suggested goals (iMessage 30min, Gmail 1hr, Slack 15min)

### 👥 Contacts
- Per-contact response time analytics
- Fastest/slowest responders ranking
- iMessage vs SMS service filter
- Contact detail sheets with response distribution chart
- Sparkline trend per contact
- Search by name, phone, or email

### 🔗 Supported Platforms
- **iMessage** — Local database analysis (timestamps only, never content)
- **Gmail** — OAuth 2.0 ready
- **Microsoft 365** — Graph API ready
- **Slack** — OAuth 2.0 ready

### 🔔 Notifications
- Threshold alerts (configurable: 15min to 4hr)
- Daily summary at custom time
- **Quiet hours** — suppress during sleep/focus time

### 🖥 Menu Bar
- Real-time median response time display
- Pending count with badge
- Response grade (A+/B/C)
- Trend percentage vs previous week
- Copy stats to clipboard
- Quick access to dashboard and settings

### 📱 Widget
- Small/Medium/Large widget sizes
- **Real iMessage data** (reads chat.db directly)
- Grade badge and pending count
- Configurable time range (Today/Week/Month)
- Goal progress bar

### 🗣 Siri & Shortcuts
- "Get my response time" — median with platform filter
- "Check my response goals" — grade + progress + median
- "Who haven't I responded to?" — pending responses list
- "Sync Response Time" — trigger sync with stats

### ⌨️ Keyboard Shortcuts
- ⌘1-5 — Switch tabs
- ⌘R — Sync now
- ⌘, — Settings

### ♿ Accessibility
- VoiceOver labels on dashboard cards, stats, contacts
- Tooltips on score components
- High contrast color coding

### 🔒 Privacy First
- **100% local processing** — All data stays on your device
- **Metadata only** — Never reads message content
- **No cloud** — No accounts, no telemetry, no tracking
- **One-click deletion** — Remove all data anytime
- **Onboarding** — Permission check with auto-setup

### 📤 Export
- CSV, JSON, and Markdown summary report
- Save to file or clipboard

## Tech Stack
- **Swift 6** with strict concurrency
- **SwiftUI** for all UI
- **SwiftData** for persistence
- **Swift Charts** for visualizations
- **App Intents** for Siri/Shortcuts
- **WidgetKit** for desktop widgets
- macOS 15+ (Sequoia)

## Building

```bash
# Generate Xcode project
cd /path/to/response-time
xcodegen generate

# Build
xcodebuild -scheme ResponseTime-macOS -destination 'platform=macOS' build

# Test (36 tests)
xcodebuild -scheme ResponseTime-macOS -destination 'platform=macOS' test
```

## Requirements
- macOS 15.0+
- Xcode 16+
- Full Disk Access (for iMessage)

## License
MIT © Mark Allen
