import Foundation
import SwiftUI
import XCTest
@testable import HushCore
@testable import HushProviders
@testable import HushSettings
@testable import HushApp

// MARK: - 5.8 Debounced Save Coalescing + Lifecycle Flush

final class DebouncedPersistenceTests: XCTestCase {

    private func makeTempStore() -> (JSONSettingsStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("settings.json")
        return (JSONSettingsStore(fileURL: url), dir)
    }

    @MainActor
    func testRapidMutationsCoalesceIntoOneWrite() async throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settingsStore: store,
            registry: registry
        )

        // Rapid mutations within debounce interval
        container.settings.parameters.temperature = 0.1
        container.settings.parameters.temperature = 0.2
        container.settings.parameters.temperature = 0.3

        // Immediately after mutations, file may not exist yet (debounce pending)
        _ = FileManager.default.fileExists(atPath: store.fileURL.path)

        // Wait for debounce to fire (1 second + margin)
        try await Task.sleep(for: .milliseconds(1500))

        // Now the file should exist with the FINAL value
        let loaded = try store.load()
        XCTAssertEqual(loaded.parameters.temperature, 0.3)
    }

    @MainActor
    func testSpacedMutationsProduceSeparateWrites() async throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settingsStore: store,
            registry: registry
        )

        // First mutation
        container.settings.parameters.temperature = 0.1
        try await Task.sleep(for: .milliseconds(1500))

        // Verify first write landed
        let firstLoad = try store.load()
        XCTAssertEqual(firstLoad.parameters.temperature, 0.1)

        // Second mutation after debounce period
        container.settings.parameters.temperature = 0.9
        try await Task.sleep(for: .milliseconds(1500))

        // Verify second write landed
        let secondLoad = try store.load()
        XCTAssertEqual(secondLoad.parameters.temperature, 0.9)
    }

    @MainActor
    func testFlushForcesImmediatePersistence() async throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settingsStore: store,
            registry: registry
        )

        // Mutate settings
        container.settings.parameters.temperature = 0.42

        // Flush immediately — no waiting for debounce
        container.flushSettings()

        // File should contain the value now
        let loaded = try store.load()
        XCTAssertEqual(loaded.parameters.temperature, 0.42)
    }

    @MainActor
    func testFlushCancelsPendingDebounce() async throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settingsStore: store,
            registry: registry
        )

        // Mutate — starts debounce timer
        container.settings.parameters.temperature = 0.5

        // Flush immediately
        container.flushSettings()

        // isDirty should be false after successful flush
        XCTAssertFalse(container.isDirty)

        // Verify persisted
        let loaded = try store.load()
        XCTAssertEqual(loaded.parameters.temperature, 0.5)
    }

    @MainActor
    func testFlushWithNoDirtyIsNoOp() async throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settingsStore: store,
            registry: registry
        )

        // No mutations — flush should be a no-op
        container.flushSettings()

        // File should not exist (no write occurred)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @MainActor
    func testScenePhaseBackgroundFlushesDirtySettings() async throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settingsStore: store,
            registry: registry
        )

        container.settings.parameters.temperature = 0.66
        container.handleScenePhaseChange(.background)

        let loaded = try store.load()
        XCTAssertEqual(loaded.parameters.temperature, 0.66)
        XCTAssertFalse(container.isDirty)
    }

    @MainActor
    func testScenePhaseInactiveFlushesDirtySettings() async throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settingsStore: store,
            registry: registry
        )

        container.settings.parameters.temperature = 0.73
        container.handleScenePhaseChange(.inactive)

        let loaded = try store.load()
        XCTAssertEqual(loaded.parameters.temperature, 0.73)
        XCTAssertFalse(container.isDirty)
    }

    @MainActor
    func testScenePhaseActiveDoesNotForceFlush() async throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settingsStore: store,
            registry: registry
        )

        container.settings.parameters.temperature = 0.81
        container.handleScenePhaseChange(.active)

        XCTAssertTrue(container.isDirty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}

// MARK: - 5.9 Persistence Failure Visibility and Retry

final class PersistenceFailureTests: XCTestCase {

    @MainActor
    func testFailedSaveKeepsDirtyForRetry() async throws {
        // Use a path that will fail to write (read-only directory)
        let badURL = URL(fileURLWithPath: "/nonexistent-readonly/settings.json")
        let badStore = JSONSettingsStore(fileURL: badURL)

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settingsStore: badStore,
            registry: registry
        )

        // Mutate and try to flush
        container.settings.parameters.temperature = 0.5
        container.flushSettings()

        // Save should have failed — dirty flag preserved for retry
        XCTAssertTrue(container.isDirty)
        XCTAssertTrue(container.statusMessage.contains("Failed to save"))
    }

    @MainActor
    func testRetryOnNextFlush() async throws {
        // First: use a bad path so save fails
        let badURL = URL(fileURLWithPath: "/nonexistent-readonly/settings.json")
        let badStore = JSONSettingsStore(fileURL: badURL)

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settingsStore: badStore,
            registry: registry
        )

        container.settings.parameters.temperature = 0.5
        container.flushSettings()

        // Should still be dirty after failed save
        XCTAssertTrue(container.isDirty)

        // Flushing again should attempt another save (still fails, but retries)
        container.flushSettings()
        XCTAssertTrue(container.isDirty) // Still dirty — path is still bad
        XCTAssertTrue(container.statusMessage.contains("Failed to save"))
    }

    @MainActor
    func testPersistenceFailureSurfacesError() async throws {
        let badURL = URL(fileURLWithPath: "/nonexistent-readonly/settings.json")
        let badStore = JSONSettingsStore(fileURL: badURL)

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settingsStore: badStore,
            registry: registry
        )

        container.settings.parameters.temperature = 0.5
        container.flushSettings()

        // Error should be visible in status
        XCTAssertTrue(container.statusMessage.contains("Failed to save"))
    }
}
