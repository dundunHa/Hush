import Foundation
@testable import Hush
import Testing

// MARK: - 6.4 Keychain Tests (using test doubles)

/// Note: These tests use a unique service prefix to avoid polluting
/// the real Keychain. Each test uses a unique provider ID.
@Suite("Keychain Adapter Tests")
struct KeychainAdapterTests {
    private let adapter = KeychainAdapter(servicePrefix: "com.dundunha.hush.test.\(UUID().uuidString)")

    @Test("Set and retrieve secret")
    func setAndRetrieve() throws {
        let providerID = "test-provider-\(UUID().uuidString)"
        try adapter.setSecret("sk-test-12345", forProviderID: providerID)

        let secret = try adapter.secret(forProviderID: providerID)
        #expect(secret == "sk-test-12345")

        // Cleanup
        try adapter.deleteSecret(forProviderID: providerID)
    }

    @Test("Update overwrites existing secret")
    func updateOverwrites() throws {
        let providerID = "test-provider-\(UUID().uuidString)"
        try adapter.setSecret("old-key", forProviderID: providerID)
        try adapter.setSecret("new-key", forProviderID: providerID)

        let secret = try adapter.secret(forProviderID: providerID)
        #expect(secret == "new-key")

        try adapter.deleteSecret(forProviderID: providerID)
    }

    @Test("Delete removes secret")
    func deleteRemoves() throws {
        let providerID = "test-provider-\(UUID().uuidString)"
        try adapter.setSecret("to-delete", forProviderID: providerID)
        try adapter.deleteSecret(forProviderID: providerID)

        #expect(throws: KeychainError.self) {
            _ = try adapter.secret(forProviderID: providerID)
        }
    }

    @Test("Missing secret throws itemNotFound")
    func missingSecretThrows() throws {
        let providerID = "nonexistent-\(UUID().uuidString)"

        #expect(throws: KeychainError.self) {
            _ = try adapter.secret(forProviderID: providerID)
        }
    }

    @Test("hasSecret returns correct status")
    func hasSecretStatus() throws {
        let providerID = "test-provider-\(UUID().uuidString)"

        #expect(!adapter.hasSecret(forProviderID: providerID))

        try adapter.setSecret("exists", forProviderID: providerID)
        #expect(adapter.hasSecret(forProviderID: providerID))

        try adapter.deleteSecret(forProviderID: providerID)
        #expect(!adapter.hasSecret(forProviderID: providerID))
    }

    @Test("CredentialRef CRUD works independently from provider ID")
    func credentialRefCRUD() throws {
        let ref = "cred-ref-\(UUID().uuidString)"
        try adapter.setSecret("sk-ref-value", forCredentialRef: ref)
        #expect(adapter.hasSecret(forCredentialRef: ref))

        let secret = try adapter.secret(forCredentialRef: ref)
        #expect(secret == "sk-ref-value")

        try adapter.deleteSecret(forCredentialRef: ref)
        #expect(!adapter.hasSecret(forCredentialRef: ref))
    }
}

// MARK: - Credential Resolver Tests

@Suite("Credential Resolver Tests")
struct CredentialResolverTests {
    @Test("Resolver returns secret when present")
    func resolverReturnsSecret() throws {
        let adapter = KeychainAdapter(servicePrefix: "com.dundunha.hush.test.\(UUID().uuidString)")
        let providerID = "test-\(UUID().uuidString)"
        try adapter.setSecret("sk-resolver-test", forProviderID: providerID)

        let resolver = CredentialResolver(keychain: adapter)
        let secret = try resolver.resolve(providerID: providerID)
        #expect(secret == "sk-resolver-test")

        try adapter.deleteSecret(forProviderID: providerID)
    }

    @Test("Resolver throws CredentialResolutionError when missing")
    func resolverThrowsWhenMissing() throws {
        let adapter = KeychainAdapter(servicePrefix: "com.dundunha.hush.test.\(UUID().uuidString)")
        let resolver = CredentialResolver(keychain: adapter)

        #expect(throws: CredentialResolutionError.self) {
            _ = try resolver.resolve(providerID: "nonexistent")
        }
    }

    @Test("Resolver resolves by credentialRef, not provider ID")
    func resolverUsesCredentialRef() throws {
        let adapter = KeychainAdapter(servicePrefix: "com.dundunha.hush.test.\(UUID().uuidString)")
        let providerID = "provider-\(UUID().uuidString)"
        let credentialRef = "cred-ref-\(UUID().uuidString)"
        try adapter.setSecret("sk-by-ref", forCredentialRef: credentialRef)

        let resolver = CredentialResolver(keychain: adapter)
        let secret = try resolver.resolve(providerID: providerID, credentialRef: credentialRef)
        #expect(secret == "sk-by-ref")

        #expect(throws: CredentialResolutionError.self) {
            _ = try resolver.resolve(providerID: providerID, credentialRef: providerID)
        }

        try adapter.deleteSecret(forCredentialRef: credentialRef)
    }

    @Test("Resolver error descriptions do not leak secret material")
    func resolverErrorRedactsSecret() throws {
        let sentinel = "sk-secret-sentinel-123"
        let resolver = CredentialResolver(secretStore: FailingSecretStore(secret: sentinel))

        do {
            _ = try resolver.resolve(providerID: "provider", credentialRef: "cred-ref")
            #expect(Bool(false), "Expected resolver to throw")
        } catch let error as CredentialResolutionError {
            let message = error.errorDescription ?? ""
            #expect(!message.contains(sentinel))
        }
    }
}

private struct FailingSecretStore: KeychainSecretStore {
    let secret: String

    func secret(forCredentialRef _: String) throws -> String {
        throw FailingSecretStoreError(detail: "upstream failure with \(secret)")
    }
}

private struct FailingSecretStoreError: Error, LocalizedError {
    let detail: String
    var errorDescription: String? {
        detail
    }
}
