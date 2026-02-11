import Foundation

// MARK: - Credential Resolution Error

/// Errors that occur when resolving provider credentials from Keychain.
public enum CredentialResolutionError: Error, Sendable, Equatable {
    /// No credential reference is configured for the provider.
    case noCredentialConfigured(providerID: String)
    /// The Keychain item referenced by the credential ref is missing or inaccessible.
    case keychainItemMissing(providerID: String, underlyingError: String)
}

extension CredentialResolutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .noCredentialConfigured(id):
            return "No API key configured for provider '\(id)'. Please add your API key in Settings."
        case let .keychainItemMissing(id, detail):
            return "Could not retrieve API key for provider '\(id)': \(detail)"
        }
    }
}

// MARK: - Credential Resolver

/// Resolves provider API keys by reading from Keychain.
/// Fails explicitly if the credential is missing or inaccessible.
public nonisolated struct CredentialResolver: Sendable {
    private let secretStore: any KeychainSecretStore

    public nonisolated init(keychain: KeychainAdapter = KeychainAdapter()) {
        secretStore = keychain
    }

    public nonisolated init(secretStore: any KeychainSecretStore) {
        self.secretStore = secretStore
    }

    /// Resolves the API key for a provider from Keychain using the configured credential reference.
    ///
    /// - Parameter providerID: The provider identifier.
    /// - Parameter credentialRef: Opaque reference key persisted in configuration.
    /// - Returns: The secret API key string.
    /// - Throws: `CredentialResolutionError` if missing or inaccessible.
    public func resolve(providerID: String, credentialRef: String?) throws -> String {
        guard let ref = credentialRef?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty else {
            throw CredentialResolutionError.noCredentialConfigured(providerID: providerID)
        }

        do {
            return try secretStore.secret(forCredentialRef: ref)
        } catch let error as KeychainError {
            switch error {
            case .itemNotFound:
                throw CredentialResolutionError.keychainItemMissing(
                    providerID: providerID,
                    underlyingError: "Credential reference not found in Keychain"
                )
            default:
                throw CredentialResolutionError.keychainItemMissing(
                    providerID: providerID,
                    underlyingError: "Unable to access credential from Keychain"
                )
            }
        } catch {
            throw CredentialResolutionError.keychainItemMissing(
                providerID: providerID,
                underlyingError: "Unable to access credential from Keychain"
            )
        }
    }

    /// Backward-compatible resolver that uses provider ID as credential reference.
    public func resolve(providerID: String) throws -> String {
        try resolve(providerID: providerID, credentialRef: providerID)
    }
}
