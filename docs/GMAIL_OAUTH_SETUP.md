# Gmail OAuth Setup Guide

This guide explains how to configure Gmail OAuth for Response Time.

## Overview

Response Time uses OAuth 2.0 with PKCE (Proof Key for Code Exchange) to securely access Gmail without storing passwords. All data stays on your device.

## Prerequisites

1. Google Cloud Platform (GCP) account
2. macOS development environment
3. Bundle ID: `com.allens.responsetime`

## Step 1: Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Click "Select a project" → "New Project"
3. **Project name:** `Response Time`
4. Click **Create**

## Step 2: Enable Gmail API

1. In your project dashboard, click "APIs & Services" → "Library"
2. Search for **Gmail API**
3. Click **Enable**

## Step 3: Configure OAuth Consent Screen

1. Go to "APIs & Services" → "OAuth consent screen"
2. **User Type:** External (for public distribution) or Internal (for personal use)
3. Click **Create**

### Application Information
- **App name:** Response Time
- **User support email:** Your email
- **App logo:** (optional) Upload your app icon
- **App domain:**
  - Application home page: `https://yourdomain.com` (or leave empty)
  - Application privacy policy: `https://yourdomain.com/privacy` (or leave empty for testing)
  - Application terms of service: `https://yourdomain.com/terms` (or leave empty)
- **Authorized domains:** Leave empty for testing
- **Developer contact information:** Your email

Click **Save and Continue**

### Scopes
1. Click **Add or Remove Scopes**
2. Filter for "Gmail API"
3. Select: `https://www.googleapis.com/auth/gmail.readonly`
   - **Description:** Read-only access to Gmail messages and settings
   - **Why needed:** To fetch message metadata (timestamps, headers) for response time analysis
4. Click **Update** → **Save and Continue**

### Test Users (if External app type and not verified)
1. Click **Add Users**
2. Add your Gmail address for testing
3. Click **Save and Continue**

## Step 4: Create OAuth Client ID

1. Go to "APIs & Services" → "Credentials"
2. Click **Create Credentials** → **OAuth client ID**
3. **Application type:** macOS (or Desktop app)
4. **Name:** Response Time macOS

### Authorized Redirect URIs
Add these redirect URIs:
```
com.allens.responsetime:/oauth2callback
http://localhost
```

5. Click **Create**
6. **Copy your Client ID** — you'll need this!

### ⚠️ Important: Keep Your Client Secret Secure
- The client secret will be shown once
- For native macOS apps using PKCE, the client secret is less critical but should still be protected
- Never commit the client secret to public repositories

## Step 5: Configure Response Time

1. Open `ResponseTime/Config/OAuthConfig.swift` (or create it)
2. Add your credentials:

```swift
enum OAuthConfig {
    static let gmailClientId = "YOUR_CLIENT_ID.apps.googleusercontent.com"
    static let gmailRedirectUri = "com.allens.responsetime:/oauth2callback"
    static let gmailScope = "https://www.googleapis.com/auth/gmail.readonly"
}
```

3. Update `OAuthService.swift`:
   - Replace `"YOUR_CLIENT_ID.apps.googleusercontent.com"` with your actual Client ID

## Step 6: Configure URL Scheme

Ensure `project.yml` has the correct URL scheme:

```yaml
targets:
  ResponseTime-macOS:
    info:
      CFBundleURLTypes:
        - CFBundleURLName: com.allens.responsetime
          CFBundleURLSchemes:
            - com.allens.responsetime
```

Run `xcodegen generate` after modifying.

## Step 7: Test the OAuth Flow

1. Build and run Response Time
2. Go to Settings → Platforms
3. Click **Connect Gmail**
4. You should see:
   - Browser opens to Google sign-in
   - Permission screen showing "Response Time wants to access your Gmail"
   - Redirect back to app after approval

### Expected User Flow
1. User clicks "Connect Gmail"
2. Safari/default browser opens
3. User signs in to Google (if not already)
4. Consent screen:
   > **Response Time wants to access your Google Account**
   >
   > This will allow Response Time to:
   > - Read your email messages and settings
   >
   > **Why is this needed?**
   > Response Time analyzes message timestamps to calculate response times. No message content is accessed or stored.
5. User clicks **Allow**
6. Browser redirects to app with authorization code
7. App exchanges code for access token + refresh token
8. Tokens stored in macOS Keychain (secure)

## Step 8: Verify Token Storage

After successful auth, tokens should be stored in Keychain:

```bash
# Check if tokens are stored
security find-generic-password -s "com.allens.responsetime" -a "oauth_gmail"
```

## Quota and Limits

**Gmail API Free Tier:**
- **Daily quota:** 1 billion quota units
- **Read requests:** 5 units per message.get
- **List requests:** 5 units per message.list
- **Batch requests:** Recommended to reduce overhead

### Estimate
- Average user with 10,000 emails/year
- Initial sync: ~50,000 units (10,000 list + 10,000 × 5 get)
- Daily incremental sync: ~250 units (50 new emails × 5)
- **Well within free tier limits**

## Privacy Considerations

### What We Access
- ✅ Message timestamps (Date header)
- ✅ From/To headers (for conversation threading)
- ✅ Message-ID, In-Reply-To, References (for threading)
- ✅ Subject line (for threading)

### What We DON'T Access
- ❌ Message body/content
- ❌ Attachments
- ❌ Labels beyond inbox/sent
- ❌ Contacts (except as derived from headers)

### Scope Justification
- `gmail.readonly`: Minimal scope for metadata access
- We explicitly request only `format=metadata` in API calls
- No write/send/modify permissions requested

## Production Checklist

Before releasing to App Store:

- [ ] Remove test users from OAuth consent screen
- [ ] Submit for OAuth verification (if >100 users)
- [ ] Add Privacy Policy URL to consent screen
- [ ] Verify App Sandbox compatibility
- [ ] Ensure Privacy Manifest declares Gmail API usage
- [ ] Test token refresh flow (tokens expire after 1 hour)
- [ ] Implement rate limiting (stay under quota)
- [ ] Handle all error cases:
  - [ ] Network errors
  - [ ] Token expiration
  - [ ] Permission denied
  - [ ] Quota exceeded

## App Store Verification

For OAuth verification (required if >100 users):

1. **Prepare documentation:**
   - Privacy policy explaining data usage
   - Video demonstrating the OAuth flow
   - Screenshots of permission prompts
   - Explanation of why readonly scope is needed

2. **Verification timeline:**
   - Initial review: 3-5 business days
   - Follow-up questions: 1-2 weeks typical
   - Total: 2-6 weeks

3. **Common rejection reasons:**
   - Overly broad scopes (we only use readonly, so should be fine)
   - Missing privacy policy
   - Unclear scope justification

## Troubleshooting

### "Error: redirect_uri_mismatch"
- Verify redirect URI in Google Console exactly matches code
- Ensure no trailing slashes
- Check for typos in bundle ID

### "Error: invalid_client"
- Client ID is incorrect
- Client ID doesn't match the one configured in Google Console

### "Error: access_denied"
- User clicked "Deny" on consent screen
- User canceled the flow

### "Error: invalid_grant"
- Authorization code already used (codes are single-use)
- Code expired (10 minutes)
- Implement refresh token flow instead of re-auth

### "Error 403: insufficientPermissions"
- User's Gmail account has restricted API access
- Check that Gmail API is enabled in GCP
- Verify scope is correctly requested

### Token Refresh Fails
- Refresh tokens are long-lived but can be revoked
- User revoked access via Google account settings
- Prompt re-authentication

## Security Best Practices

1. **Never log tokens**
   - Use `[REDACTED]` in logs instead of actual token values

2. **Keychain storage**
   - Tokens stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
   - Not synced via iCloud

3. **HTTPS only**
   - All API calls use TLS
   - Certificate pinning (optional but recommended)

4. **PKCE**
   - Proof Key for Code Exchange prevents authorization code interception
   - Required for native apps

5. **Rotation**
   - Access tokens expire after 1 hour
   - Refresh tokens are long-lived (check expiration on refresh)

## References

- [Gmail API Documentation](https://developers.google.com/gmail/api)
- [OAuth 2.0 for Mobile & Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [PKCE Specification (RFC 7636)](https://tools.ietf.org/html/rfc7636)
- [Google OAuth Verification Process](https://support.google.com/cloud/answer/9110914)

## Support

If you encounter issues:
1. Check Google Cloud Console → APIs & Services → Dashboard for errors
2. Review quota usage
3. Check [Gmail API Status](https://status.cloud.google.com/)
4. Verify your app's OAuth consent screen is approved

---

**Last Updated:** 2025-02-14  
**Version:** 1.0
