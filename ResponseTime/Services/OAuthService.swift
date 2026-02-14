import SwiftUI
import AuthenticationServices
import Security
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - OAuth Service

@Observable
@MainActor
class OAuthService {
    static let shared = OAuthService()
    
    var isAuthenticating = false
    var error: OAuthError?
    
    enum OAuthError: LocalizedError {
        case authFailed(String)
        case tokenStorageFailed
        case tokenRetrievalFailed
        case networkError
        case cancelled
        
        var errorDescription: String? {
            switch self {
            case .authFailed(let msg): return "Authentication failed: \(msg)"
            case .tokenStorageFailed: return "Failed to store credentials securely"
            case .tokenRetrievalFailed: return "Failed to retrieve stored credentials"
            case .networkError: return "Network connection error"
            case .cancelled: return "Authentication was cancelled"
            }
        }
    }
    
    // MARK: - Gmail OAuth
    
    func authenticateGmail() async throws -> OAuthTokens {
        guard OAuthConfig.isGmailConfigured else {
            throw OAuthError.authFailed("Gmail OAuth not configured. See docs/GMAIL_OAUTH_SETUP.md")
        }
        
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        var components = URLComponents(string: OAuthConfig.gmailAuthEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: OAuthConfig.gmailClientId),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.gmailRedirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: OAuthConfig.gmailScope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let authURL = components.url else {
            throw OAuthError.authFailed("Invalid auth URL")
        }
        
        // Perform OAuth flow
        let callbackURL = try await performOAuthFlow(authURL: authURL, callbackScheme: "com.allens.responsetime")
        
        // Extract authorization code
        guard let code = extractCode(from: callbackURL) else {
            throw OAuthError.authFailed("No authorization code received")
        }
        
        // Exchange code for tokens
        let tokens = try await exchangeCodeForGmailTokens(
            code: code,
            codeVerifier: codeVerifier
        )
        
        // Store tokens securely
        try storeTokens(tokens, for: .gmail)
        
        return tokens
    }
    
    /// Exchange authorization code for access/refresh tokens
    private func exchangeCodeForGmailTokens(code: String, codeVerifier: String) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: OAuthConfig.gmailTokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: OAuthConfig.gmailClientId),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.gmailRedirectUri)
        ]
        
        request.httpBody = components.query?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorString = String(data: data, encoding: .utf8) {
                throw OAuthError.authFailed("Token exchange failed: \(errorString)")
            }
            throw OAuthError.authFailed("Token exchange failed with status \(httpResponse.statusCode)")
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
            let scope: String?
            let token_type: String
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        return OAuthTokens(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in)),
            scope: tokenResponse.scope
        )
    }
    
    // MARK: - Microsoft OAuth
    
    func authenticateOutlook() async throws -> OAuthTokens {
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        // Microsoft OAuth configuration
        let clientId = "YOUR_CLIENT_ID"
        let redirectUri = "msauth.com.allens.responsetime://auth"
        let scope = "Mail.Read offline_access"
        
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        var components = URLComponents(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        guard let authURL = components.url else {
            throw OAuthError.authFailed("Invalid auth URL")
        }
        
        let callbackURL = try await performOAuthFlow(authURL: authURL, callbackScheme: "msauth.com.allens.responsetime")
        
        guard let code = extractCode(from: callbackURL) else {
            throw OAuthError.authFailed("No authorization code received")
        }
        
        let tokens = try await exchangeCodeForTokens(
            code: code,
            codeVerifier: codeVerifier,
            platform: .outlook
        )
        
        try storeTokens(tokens, for: .outlook)
        
        return tokens
    }
    
    // MARK: - Slack OAuth
    
    func authenticateSlack() async throws -> OAuthTokens {
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        // Slack OAuth configuration
        let clientId = "YOUR_CLIENT_ID"
        let redirectUri = "com.allens.responsetime://slack/callback"
        let scope = "im:history,mpim:history"
        
        var components = URLComponents(string: "https://slack.com/oauth/v2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "user_scope", value: "identify")
        ]
        
        guard let authURL = components.url else {
            throw OAuthError.authFailed("Invalid auth URL")
        }
        
        let callbackURL = try await performOAuthFlow(authURL: authURL, callbackScheme: "com.allens.responsetime")
        
        guard let code = extractCode(from: callbackURL) else {
            throw OAuthError.authFailed("No authorization code received")
        }
        
        let tokens = try await exchangeCodeForTokens(
            code: code,
            codeVerifier: nil,
            platform: .slack
        )
        
        try storeTokens(tokens, for: .slack)
        
        return tokens
    }
    
    // MARK: - Token Management
    
    func getStoredTokens(for platform: Platform) -> OAuthTokens? {
        guard let data = KeychainManager.shared.retrieve(key: "oauth_\(platform.rawValue)") else {
            return nil
        }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }
    
    func refreshTokens(for platform: Platform) async throws -> OAuthTokens {
        guard let current = getStoredTokens(for: platform),
              let refreshToken = current.refreshToken else {
            throw OAuthError.tokenRetrievalFailed
        }
        
        let newTokens: OAuthTokens
        
        switch platform {
        case .gmail:
            newTokens = try await refreshGmailTokens(refreshToken: refreshToken)
        case .outlook:
            newTokens = try await refreshMicrosoftTokens(refreshToken: refreshToken)
        case .slack:
            // Slack tokens don't typically need refresh - they're long-lived
            return current
        case .imessage:
            // iMessage doesn't use OAuth
            return current
        }
        
        try storeTokens(newTokens, for: platform)
        return newTokens
    }
    
    private func refreshGmailTokens(refreshToken: String) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: OAuthConfig.gmailTokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: OAuthConfig.gmailClientId),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        
        request.httpBody = components.query?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.authFailed("Token refresh failed")
        }
        
        struct RefreshResponse: Codable {
            let access_token: String
            let expires_in: Int
            let scope: String?
        }
        
        let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)
        
        return OAuthTokens(
            accessToken: refreshResponse.access_token,
            refreshToken: refreshToken, // Refresh token stays the same
            expiresAt: Date().addingTimeInterval(TimeInterval(refreshResponse.expires_in)),
            scope: refreshResponse.scope
        )
    }
    
    private func refreshMicrosoftTokens(refreshToken: String) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: OAuthConfig.microsoftTokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: OAuthConfig.microsoftClientId),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "scope", value: OAuthConfig.microsoftScope)
        ]
        
        request.httpBody = components.query?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.authFailed("Token refresh failed")
        }
        
        struct RefreshResponse: Codable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        
        let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)
        
        return OAuthTokens(
            accessToken: refreshResponse.access_token,
            refreshToken: refreshResponse.refresh_token ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(refreshResponse.expires_in)),
            scope: OAuthConfig.microsoftScope
        )
    }
    
    func revokeTokens(for platform: Platform) async throws {
        // Revoke with provider
        // Then clear local storage
        KeychainManager.shared.delete(key: "oauth_\(platform.rawValue)")
    }
    
    // MARK: - Private Helpers
    
    private func performOAuthFlow(authURL: URL, callbackScheme: String) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError {
                    if error.code == .canceledLogin {
                        continuation.resume(throwing: OAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: OAuthError.authFailed(error.localizedDescription))
                    }
                    return
                }
                
                if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: OAuthError.authFailed("No callback URL"))
                }
            }
            
            session.presentationContextProvider = PresentationContextProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            
            DispatchQueue.main.async {
                session.start()
            }
        }
    }
    
    private func extractCode(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "code" })?.value
    }
    
    private func exchangeCodeForTokens(code: String, codeVerifier: String?, platform: Platform) async throws -> OAuthTokens {
        // This would make the actual token exchange request
        // Placeholder for now
        return OAuthTokens(
            accessToken: "placeholder_access_token",
            refreshToken: "placeholder_refresh_token",
            expiresAt: Date().addingTimeInterval(3600),
            scope: nil
        )
    }
    
    private func storeTokens(_ tokens: OAuthTokens, for platform: Platform) throws {
        let data = try JSONEncoder().encode(tokens)
        let success = KeychainManager.shared.store(data: data, key: "oauth_\(platform.rawValue)")
        if !success {
            throw OAuthError.tokenStorageFailed
        }
    }
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        #if canImport(CryptoKit)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #else
        // Fallback without CryptoKit
        return ""
        #endif
    }
}

// MARK: - OAuth Tokens

struct OAuthTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let scope: String?
    
    var isExpired: Bool {
        Date() >= expiresAt
    }
}

// MARK: - Presentation Context Provider

class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationContextProvider()
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApp.mainWindow ?? ASPresentationAnchor()
        #else
        // For iOS, get the key window
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
        #endif
    }
}

// MARK: - Keychain Manager

final class KeychainManager: Sendable {
    static let shared = KeychainManager()
    
    private init() {}
    
    func store(data: Data, key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.allens.responsetime",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func retrieve(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.allens.responsetime",
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.allens.responsetime"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
