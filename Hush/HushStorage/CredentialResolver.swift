import Foundation

// MARK: - Credential Resolution Error

/// Errors that occur when resolving provider credentials from persisted provider configuration.
public enum CredentialResolutionError: Error, Sendable, Equatable {
    /// No persisted API key is configured for the provider.
    case noCredentialConfigured(providerID: String)
}

extension CredentialResolutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .noCredentialConfigured(id):
            return "No API key configured for provider '\(id)'. Please add your API key in Settings."
        }
    }
}

// MARK: - Credential Resolver

/// Resolves provider API keys from persisted provider configuration.
/// Fails explicitly if the credential is missing.
public nonisolated struct CredentialResolver: Sendable {
    public nonisolated init() {}

    /// Resolves the API key for a provider from its stored provider configuration.
    ///
    /// - Parameter providerID: The provider identifier.
    /// - Parameter apiKey: Persisted API key from provider configuration.
    /// - Returns: The trimmed API key string.
    /// - Throws: `CredentialResolutionError` if missing.
    public func resolve(providerID: String, apiKey: String?) throws -> String {
        guard let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            throw CredentialResolutionError.noCredentialConfigured(providerID: providerID)
        }
        return trimmed
    }
}
