# Response Time

A privacy-first app that analyzes your personal response times across messaging platforms.

![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iOS%20%7C%20iPadOS-blue)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### 📊 Dashboard
- Real-time response time metrics
- Trend visualization with charts
- Platform breakdown
- Goal progress tracking

### 🔗 Supported Platforms
- **Gmail** - OAuth 2.0 integration with Google APIs
- **Microsoft 365** - Graph API with delta sync support
- **Slack** - DM and mention tracking
- **iMessage** - Local database analysis (requires permissions)

### 🔒 Privacy First
- **100% local processing** - All data stays on your device
- **Metadata only** - We never read message content
- **No cloud required** - Your data is yours
- **One-click deletion** - Remove all data anytime

### 📈 Analytics
- Response time trends over time
- Working hours vs. off-hours analysis
- Contact-level metrics
- Distribution charts
- Weekly patterns

### 🎯 Goals
- Set response time targets by platform
- Track progress with visual indicators
- Get insights when falling behind

### 🖥️ Platform Features

#### macOS
- Menu bar extra for quick metrics
- Desktop widgets (small, medium, large)
- Settings preferences window
- Keyboard shortcuts

#### iOS & iPadOS
- Native tab-based navigation
- Home screen widgets
- Siri Shortcuts integration
- Share sheet export

## Requirements

- **macOS** 15.0 (Sequoia) or later
- **iOS/iPadOS** 18.0 or later
- Xcode 16.0+ for development

## Building

### Prerequisites
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build Steps

```bash
# Clone the repository
git clone https://github.com/markoalleno/response-time.git
cd response-time

# Generate Xcode project
xcodegen generate

# Build for macOS
xcodebuild -scheme ResponseTime-macOS -destination 'platform=macOS' build

# Build for iOS Simulator
xcodebuild -scheme ResponseTime-iOS -destination 'generic/platform=iOS Simulator' build
```

## OAuth Configuration

To connect to messaging platforms, you'll need to configure OAuth credentials:

### Gmail
1. Create a project in [Google Cloud Console](https://console.cloud.google.com)
2. Enable Gmail API
3. Create OAuth 2.0 credentials
4. Update `CLIENT_ID` in `OAuthService.swift`

### Microsoft 365
1. Register an app in [Azure Portal](https://portal.azure.com)
2. Configure redirect URI
3. Add Mail.Read permission
4. Update `CLIENT_ID` in `OAuthService.swift`

### Slack
1. Create an app at [api.slack.com](https://api.slack.com/apps)
2. Configure OAuth scopes
3. Update `CLIENT_ID` in `OAuthService.swift`

## Architecture

### Tech Stack
- **Swift 6** with strict concurrency
- **SwiftUI** for all UI
- **SwiftData** for persistence
- **Swift Charts** for visualizations
- **App Intents** for Siri/Shortcuts
- **WidgetKit** for home screen widgets

### Project Structure
```
ResponseTime/
├── Models/           # SwiftData models
├── Views/            # SwiftUI views
├── Services/         # Business logic
│   ├── Connectors/   # Platform API connectors
│   └── ...
├── Assets.xcassets/  # Images and colors
└── PrivacyInfo.xcprivacy

ResponseTimeWidget/   # Widget extension
```

### Key Components
- **SyncCoordinator** - Orchestrates sync across platforms
- **ResponseAnalyzer** - Computes metrics and response windows
- **GmailConnector/MicrosoftConnector/SlackConnector** - Platform-specific API clients
- **ExportService** - CSV and JSON export

## Privacy

Response Time is designed with privacy as a core principle:

- All data processing happens locally on your device
- Only message metadata (timestamps, participants) is accessed
- Message content is never read or stored
- No analytics or telemetry is collected
- Optional iCloud sync uses your private CloudKit container

See [Privacy Policy](https://example.com/privacy) for details.

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting a PR.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Apple's Swift and SwiftUI teams
- The XcodeGen project
- All contributors and testers

---

Made with ❤️ by Mark Allen
