import Foundation
import XCTest
@testable import HushCore
@testable import HushSettings

final class SettingsStoreTests: XCTestCase {
    func testLoadReturnsDefaultWhenFileMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("settings.json")
        let store = JSONSettingsStore(fileURL: fileURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded, .default)
    }

    func testSaveAndLoadRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("settings.json")
        let store = JSONSettingsStore(fileURL: fileURL)

        var settings = AppSettings.default
        settings.selectedModelID = "mock-vision-1"
        settings.parameters.temperature = 0.25
        settings.parameters.maxTokens = 4096

        try store.save(settings)
        let loaded = try store.load()

        XCTAssertEqual(loaded, settings)
    }
}

