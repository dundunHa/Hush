#!/usr/bin/env swift

import Foundation

// MARK: - CLI

func printUsage() {
    let usage = """
    Usage: perf-report.swift [OPTIONS] [FILE]

    Parse PerfTrace JSON log lines and generate a summary report.

    Input: JSON lines from os.Logger (PerfTrace subsystem) via stdin or FILE.
           Accepts both raw JSON lines and `log show --style json` output.

    Options:
      --help        Show this help message
      --raw         Treat input as raw JSON lines (one per line), not `log show` output
      --json        Output summary as JSON (default)
      --text        Output summary as human-readable text

    Examples:
      log show --style json --predicate 'subsystem == "com.hush.app" AND category == "PerfTrace"' --last 5m | swift scripts/perf-report.swift
      swift scripts/perf-report.swift --raw < perf-lines.jsonl
      swift scripts/perf-report.swift perf-log.json
    """
    print(usage)
}

// MARK: - Models

struct PerfEntry {
    let event: String
    let type: String
    let value: Double
    let ts: Int64
}

struct EventSummary: Codable {
    let event: String
    let type: String
    let count: Int
    let min: Double
    let max: Double
    let mean: Double
    let p50: Double
    let p95: Double
    let p99: Double
}

struct Report: Codable {
    let generatedAt: String
    let totalEntries: Int
    let events: [EventSummary]
}

// MARK: - Parsing

func parseRawLine(_ line: String) -> PerfEntry? {
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let event = obj["event"] as? String,
          let type = obj["type"] as? String,
          let ts = obj["ts"] as? Int64
    else { return nil }

    let value: Double
    if let intVal = obj["value"] as? Int {
        value = Double(intVal)
    } else if let doubleVal = obj["value"] as? Double {
        value = doubleVal
    } else {
        return nil
    }

    return PerfEntry(event: event, type: type, value: value, ts: ts)
}

func parseLogShowOutput(_ data: Data) -> [PerfEntry] {
    guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return []
    }
    var entries: [PerfEntry] = []
    for record in arr {
        guard let message = record["eventMessage"] as? String else { continue }
        if let entry = parseRawLine(message) {
            entries.append(entry)
        }
    }
    return entries
}

func parseInput(data: Data, rawMode: Bool) -> [PerfEntry] {
    if rawMode {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return parseRawLine(trimmed)
        }
    }

    let logShowEntries = parseLogShowOutput(data)
    if !logShowEntries.isEmpty {
        return logShowEntries
    }

    // Fallback: try line-by-line parsing.
    // `log show --style json` may emit NDJSON (one JSON object per line)
    // instead of a single JSON array, so we try both log-show record parsing
    // and raw PerfTrace line parsing for each line.
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    return text.components(separatedBy: .newlines).compactMap { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Try as a log-show record (NDJSON object with eventMessage key)
        if let lineData = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
           let message = obj["eventMessage"] as? String,
           let entry = parseRawLine(message)
        {
            return entry
        }

        // Try as a raw PerfTrace JSON line
        return parseRawLine(trimmed)
    }
}

// MARK: - Statistics

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = p / 100.0 * Double(sorted.count - 1)
    let lower = Int(index)
    let upper = min(lower + 1, sorted.count - 1)
    let fraction = index - Double(lower)
    return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
}

func buildReport(entries: [PerfEntry]) -> Report {
    var grouped: [String: [PerfEntry]] = [:]
    for entry in entries {
        grouped[entry.event, default: []].append(entry)
    }

    var summaries: [EventSummary] = []
    for (event, group) in grouped.sorted(by: { $0.key < $1.key }) {
        let type = group.first?.type ?? "count"
        let values = group.map(\.value).sorted()
        let count = values.count
        let minVal = values.first ?? 0
        let maxVal = values.last ?? 0
        let mean = values.reduce(0, +) / Double(max(1, count))

        summaries.append(EventSummary(
            event: event,
            type: type,
            count: count,
            min: round(minVal * 100) / 100,
            max: round(maxVal * 100) / 100,
            mean: round(mean * 100) / 100,
            p50: round(percentile(values, 50) * 100) / 100,
            p95: round(percentile(values, 95) * 100) / 100,
            p99: round(percentile(values, 99) * 100) / 100
        ))
    }

    let formatter = ISO8601DateFormatter()
    return Report(
        generatedAt: formatter.string(from: Date()),
        totalEntries: entries.count,
        events: summaries
    )
}

// MARK: - Output

func outputJSON(_ report: Report) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(report) else {
        fputs("Error: Failed to encode report\n", stderr)
        exit(1)
    }
    print(String(data: data, encoding: .utf8)!)
}

func outputText(_ report: Report) {
    print("=== PerfTrace Report ===")
    print("Generated: \(report.generatedAt)")
    print("Total entries: \(report.totalEntries)")
    print("")

    if report.events.isEmpty {
        print("No events found.")
        return
    }

    for summary in report.events {
        let unit = summary.type == "duration_ms" ? "ms" : ""
        print("[\(summary.event)] (\(summary.type), n=\(summary.count))")
        print("  min=\(summary.min)\(unit)  max=\(summary.max)\(unit)  mean=\(summary.mean)\(unit)")
        print("  p50=\(summary.p50)\(unit)  p95=\(summary.p95)\(unit)  p99=\(summary.p99)\(unit)")
        print("")
    }
}

// MARK: - Main

var args = CommandLine.arguments.dropFirst()
var rawMode = false
var textOutput = false
var inputFile: String?

while let arg = args.first {
    args = args.dropFirst()
    switch arg {
    case "--help", "-h":
        printUsage()
        exit(0)
    case "--raw":
        rawMode = true
    case "--json":
        textOutput = false
    case "--text":
        textOutput = true
    default:
        inputFile = arg
    }
}

let inputData: Data
if let file = inputFile {
    guard let data = FileManager.default.contents(atPath: file) else {
        fputs("Error: Cannot read file: \(file)\n", stderr)
        exit(1)
    }
    inputData = data
} else {
    inputData = FileHandle.standardInput.readDataToEndOfFile()
}

let entries = parseInput(data: inputData, rawMode: rawMode)
let report = buildReport(entries: entries)

if textOutput {
    outputText(report)
} else {
    outputJSON(report)
}
