# Response Time

> Privacy-first macOS app for analyzing personal response times across communication platforms.

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-orange?logo=swift" alt="Swift 6" />
  <img src="https://img.shields.io/badge/macOS-15%2B-blue?logo=apple" alt="macOS 15+" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" />
</p>

## Overview

Response Time helps you understand and improve your communication responsiveness by analyzing when you receive messages and when you respond. All data is processed **locally on your device** — no cloud analytics, no data collection, just actionable insights.

### Key Features

- **📊 Dashboard** — At-a-glance metrics with median response time, trends, and goal progress
- **📈 Analytics** — Interactive charts showing trends, heatmaps, distributions, and platform breakdowns
- **🎯 Goals** — Set response time targets by platform and track your progress
- **🔒 Privacy-First** — 100% local processing, metadata only, no message content
- **📱 Multi-Platform** — Gmail, Outlook, Slack, and iMessage support
- **📌 Menu Bar** — Quick-glance metrics without opening the full app
- **📲 Widgets** — Desktop widgets in small, medium, and large sizes

## Privacy

Response Time is designed with privacy as the foundation, not an afterthought:

| Feature | Details |
|---------|---------|
| **Local Processing** | All analytics computed on-device |
| **No Cloud** | Zero data sent to external servers |
| **Metadata Only** | Never reads message content — just timestamps and participants |
| **Your Data** | One-click data deletion, CSV export |
| **Open Source** | Audit the code yourself |

## Screenshots

*Coming soon — build from source to see the app in action.*

## Getting Started

### Requirements

- macOS 15 (Sequoia) or later
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)

### Build

```bash
# Clone the repo
git clone https://github.com/markoalleno/response-time.git
cd response-time

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -target ResponseTime -destination 'platform=macOS' build

# Or open in Xcode
open ResponseTime.xcodeproj
```

### Configure OAuth (Required for Platform Connections)

To connect Gmail, Outlook, or Slack, you'll need to set up OAuth credentials:

#### Gmail
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project and enable Gmail API
3. Create OAuth 2.0 credentials (macOS app type)
4. Add your client ID to `OAuthService.swift`

#### Microsoft Outlook
1. Go to [Azure Portal](https://portal.azure.com/)
2. Register an application
3. Add `Mail.Read` permission
4. Add your client ID to `OAuthService.swift`

#### Slack
1. Go to [Slack API](https://api.slack.com/apps)
2. Create a new app
3. Add `im:history` and `mpim:history` scopes
4. Add your client ID to `OAuthService.swift`

## Architecture

```
ResponseTime/
├── ResponseTimeApp.swift      # App entry point, scenes
├── Models/
│   └── Models.swift           # SwiftData models
├── Views/
│   ├── ContentView.swift      # Main navigation
│   ├── DashboardView.swift    # Dashboard (inside ContentView)
│   ├── PlatformsView.swift    # Account management
│   ├── AnalyticsView.swift    # Charts and insights
│   ├── GoalsView.swift        # Goal tracking
│   ├── SettingsView.swift     # Preferences
│   ├── MenuBarView.swift      # Menu bar extra
│   └── OnboardingView.swift   # First-run experience
└── Services/
    ├── OAuthService.swift     # OAuth 2.0 + PKCE
    └── ResponseAnalyzer.swift # Analytics engine
```

### Data Models

- **SourceAccount** — Connected platform (Gmail, Outlook, Slack, iMessage)
- **Conversation** — Thread/conversation container
- **MessageEvent** — Individual message with timestamp and direction
- **ResponseWindow** — Computed inbound→outbound response pair
- **ResponseGoal** — User-defined response time targets

## Roadmap

- [ ] Gmail API integration
- [ ] Microsoft Graph API integration
- [ ] Slack API integration
- [ ] iMessage database reader
- [ ] Background sync (SMAppService)
- [ ] Optional iCloud sync
- [ ] App Intents / Shortcuts
- [ ] Calendar context awareness

## Contributing

Contributions welcome! Please open an issue first to discuss major changes.

## License

MIT License — see [LICENSE](LICENSE) for details.

---

Built with ❤️ by [@markoalleno](https://github.com/markoalleno)
