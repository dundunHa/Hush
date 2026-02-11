import Foundation

public struct SSEEvent: Sendable, Equatable {
    public var data: String
    public var event: String?
    public var id: String?
    public var retry: Int?

    public init(data: String, event: String? = nil, id: String? = nil, retry: Int? = nil) {
        self.data = data
        self.event = event
        self.id = id
        self.retry = retry
    }
}

public struct SSEParser: Sendable {
    private var dataLines: [String] = []
    private var eventType: String?
    private var eventID: String?
    private var retryValue: Int?
    private var hasFields: Bool = false

    public init() {}

    public mutating func feedLine(_ line: String) -> [SSEEvent] {
        if line.isEmpty {
            guard hasFields else { return [] }
            let event = SSEEvent(
                data: dataLines.joined(separator: "\n"),
                event: eventType,
                id: eventID,
                retry: retryValue
            )
            reset()
            return [event]
        }

        if line.hasPrefix(":") {
            return []
        }

        let field: String
        let value: String
        if let colonIndex = line.firstIndex(of: ":") {
            field = String(line[line.startIndex ..< colonIndex])
            let afterColon = line.index(after: colonIndex)
            if afterColon < line.endIndex, line[afterColon] == " " {
                value = String(line[line.index(after: afterColon)...])
            } else {
                value = String(line[afterColon...])
            }
        } else {
            field = line
            value = ""
        }

        hasFields = true

        switch field {
        case "data":
            dataLines.append(value)
        case "event":
            eventType = value
        case "id":
            eventID = value
        case "retry":
            retryValue = Int(value)
        default:
            break
        }

        return []
    }

    private mutating func reset() {
        dataLines.removeAll()
        eventType = nil
        eventID = nil
        retryValue = nil
        hasFields = false
    }
}
