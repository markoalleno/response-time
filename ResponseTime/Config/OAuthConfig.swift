import Foundation

/// OAuth configuration for Response Time
/// 
/// ⚠️ SECURITY NOTE:
/// - Never commit actual credentials to version control
/// - For production, load from secure storage or build-time environment variables
/// - Consider using xcconfig files for credential injection
enum OAuthConfig {
    // MARK: - Gmail
    
    /// Gmail OAuth Client ID from Google Cloud Console
    /// 
    /// Setup instructions: docs/GMAIL_OAUTH_SETUP.md
    /// 
    /// To configure:
    /// 1. Create project in Google Cloud Console
    /// 2. Enable Gmail API
    /// 3. Create OAuth 2.0 Client ID (macOS/Desktop app)
    /// 4. Copy Client ID here
    static let gmailClientId = "YOUR_CLIENT_ID.apps.googleusercontent.com"
    
    /// Gmail OAuth redirect URI
    /// Must match the URL scheme registered in project.yml
    static let gmailRedirectUri = "com.allens.responsetime:/oauth2callback"
    
    /// Gmail API scopes
    /// We only request readonly access to message metadata
    static let gmailScope = "https://www.googleapis.com/auth/gmail.readonly"
    
    /// Gmail token endpoint
    static let gmailTokenEndpoint = "https://oauth2.googleapis.com/token"
    
    /// Gmail authorization endpoint
    static let gmailAuthEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    
    // MARK: - Microsoft 365
    
    /// Microsoft OAuth Client ID from Azure AD
    /// 
    /// To configure:
    /// 1. Register app in Azure Active Directory
    /// 2. Add Mail.Read permission
    /// 3. Copy Application (client) ID here
    static let microsoftClientId = "YOUR_CLIENT_ID"
    
    /// Microsoft OAuth redirect URI
    static let microsoftRedirectUri = "msauth.com.allens.responsetime://auth"
    
    /// Microsoft Graph API scopes
    static let microsoftScope = "Mail.Read offline_access"
    
    /// Microsoft token endpoint
    static let microsoftTokenEndpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
    
    /// Microsoft authorization endpoint
    static let microsoftAuthEndpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
    
    // MARK: - Slack
    
    /// Slack OAuth Client ID
    /// 
    /// To configure:
    /// 1. Create Slack app at api.slack.com/apps
    /// 2. Add OAuth scopes: im:history, mpim:history
    /// 3. Copy Client ID here
    static let slackClientId = "YOUR_CLIENT_ID"
    
    /// Slack OAuth Client Secret
    /// Note: Slack requires client secret for token exchange
    static let slackClientSecret = "YOUR_CLIENT_SECRET"
    
    /// Slack OAuth redirect URI
    static let slackRedirectUri = "com.allens.responsetime://slack/callback"
    
    /// Slack OAuth scopes
    static let slackScope = "im:history,mpim:history"
    
    /// Slack token endpoint
    static let slackTokenEndpoint = "https://slack.com/api/oauth.v2.access"
    
    /// Slack authorization endpoint
    static let slackAuthEndpoint = "https://slack.com/oauth/v2/authorize"
    
    // MARK: - Helpers
    
    /// Check if Gmail OAuth is configured
    static var isGmailConfigured: Bool {
        !gmailClientId.contains("YOUR_CLIENT_ID")
    }
    
    /// Check if Microsoft OAuth is configured
    static var isMicrosoftConfigured: Bool {
        !microsoftClientId.contains("YOUR_CLIENT_ID")
    }
    
    /// Check if Slack OAuth is configured
    static var isSlackConfigured: Bool {
        !slackClientId.contains("YOUR_CLIENT_ID")
    }
    
    /// Get configuration status for a platform
    static func isConfigured(for platform: Platform) -> Bool {
        switch platform {
        case .gmail:
            return isGmailConfigured
        case .outlook:
            return isMicrosoftConfigured
        case .slack:
            return isSlackConfigured
        case .imessage:
            return true // iMessage doesn't need OAuth
        }
    }
}
