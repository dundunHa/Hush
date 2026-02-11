import Foundation
import os

// MARK: - PerfTrace

/// Debug-only performance tracing for chat rendering hot paths.
///
/// Emits structured JSON log lines via `os.Logger` with the subsystem
/// `com.hush.app` and category `PerfTrace`. Each line follows the schema:
///
///     {"event":"<name>","type":"count"|"duration_ms","value":<number>,"ts":<unix_ms>}
///
/// In Release builds the entire type compiles away to zero overhead thanks to
/// the `#if DEBUG` guard surrounding all stored state and logic.
enum PerfTrace {
    // MARK: - Event Names

    enum Event {
        static let visibleRecompute = "visible.recompute"
        static let scrollAdjustToBottom = "scroll.adjustToBottom"
        static let textEnsureLayout = "text.ensureLayout"
        static let attachmentsReconcile = "attachments.reconcile"
        static let switchSnapshotApplied = "switch.snapshotApplied"
        static let switchLayoutReady = "switch.layoutReady"
        static let switchRichReady = "switch.richReady"
        static let switchPresentedRendered = "switch.presentedRendered"
        static let renderCacheHitRate = "switch.renderCacheHitRate"
        static let switchScenePoolPath = "switch.scenePoolPath"
        static let switchSnapshotToLayoutReady = "switch.snapshot_to_layoutReady"
        static let switchSnapshotToRichReady = "switch.snapshot_to_richReady"
    }

    // MARK: - Public Interface

    static func count(_ event: String, value: Int = 1, fields: [String: String] = [:]) {
        #if DEBUG
            emit(event: event, type: "count", value: Double(value), fields: fields)
        #endif
    }

    static func duration(_ event: String, ms: Double, fields: [String: String] = [:]) {
        #if DEBUG
            emit(event: event, type: "duration_ms", value: ms, fields: fields)
        #endif
    }

    @discardableResult
    static func measure<T>(_ event: String, fields: [String: String] = [:], body: () -> T) -> T {
        #if DEBUG
            let start = ContinuousClock.now
            let result = body()
            let elapsed = ContinuousClock.now - start
            let ms = Double(elapsed.components.attoseconds) / 1e15
            duration(event, ms: ms, fields: fields)
            return result
        #else
            return body()
        #endif
    }

    @discardableResult
    static func measureAsync<T>(_ event: String, fields: [String: String] = [:], body: () async -> T) async -> T {
        #if DEBUG
            let start = ContinuousClock.now
            let result = await body()
            let elapsed = ContinuousClock.now - start
            let ms = Double(elapsed.components.attoseconds) / 1e15
            duration(event, ms: ms, fields: fields)
            return result
        #else
            return await body()
        #endif
    }

    // MARK: - Private

    #if DEBUG
        private static let logger = Logger(subsystem: "com.hush.app", category: "PerfTrace")

        struct Record: Sendable, Equatable {
            let event: String
            let type: String
            let value: Double
            let ts: Int64
            let fields: [String: String]
        }

        final class TestRecorder: @unchecked Sendable {
            private let lock = NSLock()
            private var records: [Record] = []

            func record(_ record: Record) {
                lock.lock()
                records.append(record)
                lock.unlock()
            }

            func snapshot() -> [Record] {
                lock.lock()
                let copy = records
                lock.unlock()
                return copy
            }
        }

        @TaskLocal static var testRecorder: TestRecorder?

        private static func emit(event: String, type: String, value: Double, fields: [String: String]) {
            let ts = Int64(Date.now.timeIntervalSince1970 * 1000)
            testRecorder?.record(
                Record(
                    event: event,
                    type: type,
                    value: value,
                    ts: ts,
                    fields: fields
                )
            )
            var json = "{\"event\":\"\(event)\",\"type\":\"\(type)\",\"value\":\(formatValue(value, type: type)),\"ts\":\(ts)"
            for (key, val) in fields.sorted(by: { $0.key < $1.key }) {
                let escapedVal = val.replacingOccurrences(of: "\"", with: "\\\"")
                json += ",\"\(key)\":\"\(escapedVal)\""
            }
            json += "}"
            logger.debug("\(json, privacy: .public)")
        }

        private static func formatValue(_ value: Double, type: String) -> String {
            if type == "count" {
                return "\(Int(value))"
            }
            return String(format: "%.2f", value)
        }
    #endif
}
