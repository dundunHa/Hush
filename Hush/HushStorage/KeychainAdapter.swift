import Foundation
import Security

// MARK: - Keychain Secret Store Protocol

/// Minimal secret-store interface used by credential resolution.
public protocol KeychainSecretStore: Sendable {
    nonisolated func secret(forCredentialRef credentialRef: String) throws -> String
}

/// Writable secret-store interface used by settings save workflows.
public protocol KeychainCredentialStore: KeychainSecretStore {
    nonisolated func setSecret(_ secret: String, forCredentialRef credentialRef: String) throws
    nonisolated func hasSecret(forCredentialRef credentialRef: String) -> Bool
}

// MARK: - Keychain Error

public enum KeychainError: Error, Sendable, Equatable {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case decodingFailed

    public var localizedDescription: String {
        switch self {
        case .itemNotFound:
            return "Keychain item not found"
        case .duplicateItem:
            return "Keychain item already exists"
        case let .unexpectedStatus(status):
            return "Keychain error: \(status)"
        case .encodingFailed:
            return "Failed to encode secret for Keychain"
        case .decodingFailed:
            return "Failed to decode secret from Keychain"
        }
    }
}

// MARK: - Keychain Adapter

/// Provides CRUD operations for provider secrets stored in macOS Keychain.
/// Uses the Security framework directly. Secrets are stored as generic passwords
/// keyed by service name and account.
public nonisolated struct KeychainAdapter: Sendable {
    /// The Keychain service name prefix. Provider IDs are appended.
    private let servicePrefix: String

    public init(servicePrefix: String = "com.dundunha.hush.provider") {
        self.servicePrefix = servicePrefix
    }

    // MARK: - Public API

    /// Stores a secret for a credential reference. Overwrites if it already exists.
    public func setSecret(_ secret: String, forCredentialRef credentialRef: String) throws {
        guard !credentialRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeychainError.encodingFailed
        }

        let service = serviceName(for: credentialRef)
        guard let data = secret.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Try to update first; if not found, add new.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialRef
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Add new item
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// Reads the secret for a credential reference, or throws if not found.
    public func secret(forCredentialRef credentialRef: String) throws -> String {
        guard !credentialRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeychainError.itemNotFound
        }

        let service = serviceName(for: credentialRef)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialRef,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let secret = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return secret
    }

    /// Deletes the secret for a credential reference, if it exists.
    public func deleteSecret(forCredentialRef credentialRef: String) throws {
        let service = serviceName(for: credentialRef)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialRef
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Returns whether a secret exists for a credential reference.
    public func hasSecret(forCredentialRef credentialRef: String) -> Bool {
        let service = serviceName(for: credentialRef)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialRef,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Stores a secret for the given provider. Overwrites if it already exists.
    public func setSecret(_ secret: String, forProviderID providerID: String) throws {
        try setSecret(secret, forCredentialRef: providerID)
    }

    /// Reads the secret for the given provider, or throws if not found.
    public func secret(forProviderID providerID: String) throws -> String {
        try secret(forCredentialRef: providerID)
    }

    /// Deletes the secret for the given provider, if it exists.
    public func deleteSecret(forProviderID providerID: String) throws {
        try deleteSecret(forCredentialRef: providerID)
    }

    /// Returns whether a secret exists for the given provider.
    public func hasSecret(forProviderID providerID: String) -> Bool {
        hasSecret(forCredentialRef: providerID)
    }

    // MARK: - Private

    private func serviceName(for providerID: String) -> String {
        "\(servicePrefix).\(providerID)"
    }
}

// MARK: - Protocol Conformance

extension KeychainAdapter: KeychainCredentialStore {}
