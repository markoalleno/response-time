import Foundation
import Contacts

/// Resolves phone numbers and emails to contact names using the system Contacts database
actor ContactResolver {
    static let shared = ContactResolver()
    
    private var cache: [String: String] = [:]  // identifier → display name
    private var hasLoaded = false
    
    /// Resolve an identifier (phone/email) to a display name
    func resolve(_ identifier: String) -> String? {
        if !hasLoaded {
            loadContacts()
        }
        return cache[normalizeIdentifier(identifier)]
    }
    
    /// Resolve multiple identifiers at once
    func resolveAll(_ identifiers: [String]) -> [String: String] {
        if !hasLoaded {
            loadContacts()
        }
        var result: [String: String] = [:]
        for id in identifiers {
            if let name = cache[normalizeIdentifier(id)] {
                result[id] = name
            }
        }
        return result
    }
    
    /// Check if we have Contacts access
    func hasAccess() -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized
    }
    
    /// Request access and load contacts
    func requestAccessAndLoad() async -> Bool {
        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            if granted {
                loadContacts()
            }
            return granted
        } catch {
            return false
        }
    }
    
    // MARK: - Private
    
    private func loadContacts() {
        hasLoaded = true
        
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else { return }
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                
                guard !name.isEmpty else { return }
                
                // Map all phone numbers
                for phone in contact.phoneNumbers {
                    let normalized = self.normalizePhone(phone.value.stringValue)
                    self.cache[normalized] = name
                }
                
                // Map all emails
                for email in contact.emailAddresses {
                    let normalized = (email.value as String).lowercased()
                    self.cache[normalized] = name
                }
            }
        } catch {
            // Silently fail — contacts are optional enhancement
        }
    }
    
    private func normalizeIdentifier(_ id: String) -> String {
        if id.contains("@") {
            return id.lowercased()
        }
        return normalizePhone(id)
    }
    
    private func normalizePhone(_ phone: String) -> String {
        // Strip to just digits
        var digits = phone.filter { $0.isNumber }
        // Normalize US numbers: ensure 11 digits starting with 1
        if digits.count == 10 {
            digits = "1" + digits
        }
        if digits.count == 11 && digits.hasPrefix("1") {
            return "+\(digits)"
        }
        // Return original format with + prefix if it had one
        if phone.hasPrefix("+") {
            return "+" + digits
        }
        return digits
    }
}
