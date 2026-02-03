# CLAUDE.md — Response Time App

## Overview

Response Time is a privacy-first macOS application that analyzes and provides insights into personal response times across various messaging and notification platforms.

**Key Principles:**
- 100% local processing — no cloud analytics
- Metadata only — never reads message content
- Privacy by design — user controls all data

## Tech Stack

- **SwiftUI** — Complete UI implementation
- **SwiftData** — Local persistence
- **Swift 6** — Strict concurrency
- **WidgetKit** — Desktop widgets
- **MenuBarExtra** — Quick-glance metrics
- **ASWebAuthenticationSession** — OAuth flows

## Project Structure

```
ResponseTime/
├── ResponseTimeApp.swift      # App entry point, scenes
├── Models/
│   └── Models.swift           # SwiftData models
├── Views/
│   ├── ContentView.swift      # Main dashboard
│   ├── PlatformsView.swift    # Account management
│   ├── AnalyticsView.swift    # Charts and insights
│   ├── GoalsView.swift        # Goal tracking
│   ├── SettingsView.swift     # Preferences
│   ├── MenuBarView.swift      # Menu bar extra
│   └── OnboardingView.swift   # First-run flow
├── Services/
│   ├── OAuthService.swift     # OAuth flows for Gmail/Outlook/Slack
│   └── ResponseAnalyzer.swift # Analytics engine
└── Info.plist

ResponseTimeWidget/
├── ResponseTimeWidget.swift   # Widget implementation
├── Info.plist
└── ResponseTimeWidget.entitlements
```

## Build

```bash
cd /Users/mark/response-time
xcodegen generate
xcodebuild -scheme ResponseTime -destination 'platform=macOS' build
```

## Key Models

- **SourceAccount** — Connected platform account
- **Conversation** — Thread/conversation container
- **MessageEvent** — Individual message timestamp
- **ResponseWindow** — Computed inbound→outbound pair
- **ResponseGoal** — User-defined targets

## OAuth Configuration

Before running with real accounts, add OAuth credentials:
- Gmail: Google Cloud Console → OAuth 2.0 Client ID
- Outlook: Azure Portal → App Registration
- Slack: Slack API → Create App

Update client IDs in `OAuthService.swift`.

## Privacy Features

- Keychain storage for tokens (device-only accessibility)
- No message content access
- One-click data deletion
- CSV export for user data

## Next Steps

1. Add actual OAuth client IDs
2. Implement Gmail API connector
3. Implement Microsoft Graph connector
4. Implement Slack API connector
5. Add iMessage local database reader
6. Add background sync via SMAppService
7. Add CloudKit sync (optional)
