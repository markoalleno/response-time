import SwiftUI
import AuthenticationServices
import Security

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
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        // Gmail OAuth configuration
        // In production, these would come from Google Cloud Console
        let clientId = "YOUR_CLIENT_ID.apps.googleusercontent.com"
        let redirectUri = "com.allens.responsetime:/oauth2callback"
        let scope = "https://www.googleapis.com/auth/gmail.readonly"
        
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
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
        let tokens = try await exchangeCodeForTokens(
            code: code,
            codeVerifier: codeVerifier,
            platform: .gmail
        )
        
        // Store tokens securely
        try storeTokens(tokens, for: .gmail)
        
        return tokens
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
        
        // Perform token refresh based on platform
        // This is a placeholder - real implementation would call the appropriate endpoint
        let newTokens = OAuthTokens(
            accessToken: "new_access_token",
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(3600),
            scope: current.scope
        )
        
        try storeTokens(newTokens, for: platform)
        return newTokens
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
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - OAuth Tokens

struct OAuthTokens: Codable {
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
        NSApp.mainWindow ?? ASPresentationAnchor()
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

// Import CommonCrypto for SHA256
import CommonCrypto
