import Foundation

// MARK: - OpenAI API Models

struct OpenAIModelsResponse: Decodable {
    let data: [OpenAIModel]
}

struct OpenAIModel: Decodable {
    let id: String
    let ownedBy: String?
    let created: Int?
    let rawMetadataJSON: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
        case created
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ownedBy = try container.decodeIfPresent(String.self, forKey: .ownedBy)
        created = try container.decodeIfPresent(Int.self, forKey: .created)

        let rawContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        var rawMetadata: [String: JSONValue] = [:]
        for key in rawContainer.allKeys where key.stringValue != CodingKeys.id.rawValue {
            rawMetadata[key.stringValue] = try rawContainer.decode(JSONValue.self, forKey: key)
        }
        rawMetadataJSON = Self.encodeRawMetadata(rawMetadata)
    }

    /// Test-only initializer
    init(id: String, ownedBy: String? = nil, created: Int? = nil) {
        self.id = id
        self.ownedBy = ownedBy
        self.created = created
        var rawMetadata: [String: JSONValue] = [:]
        if let ownedBy {
            rawMetadata[CodingKeys.ownedBy.rawValue] = .string(ownedBy)
        }
        if let created {
            rawMetadata[CodingKeys.created.rawValue] = .integer(created)
        }
        rawMetadataJSON = Self.encodeRawMetadata(rawMetadata)
    }

    private static func encodeRawMetadata(_ rawMetadata: [String: JSONValue]) -> String? {
        guard !rawMetadata.isEmpty else { return nil }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(rawMetadata) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: any Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [JSONValue] = []
            while !unkeyed.isAtEnd {
                try values.append(unkeyed.decode(JSONValue.self))
            }
            self = .array(values)
            return
        }

        if let keyed = try? decoder.container(keyedBy: AnyCodingKey.self) {
            var dictionary: [String: JSONValue] = [:]
            for key in keyed.allKeys {
                dictionary[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key)
            }
            self = .object(dictionary)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .integer(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .number(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .bool(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .object(value):
            var container = encoder.container(keyedBy: AnyCodingKey.self)
            for (key, nestedValue) in value {
                guard let codingKey = AnyCodingKey(stringValue: key) else { continue }
                try container.encode(nestedValue, forKey: codingKey)
            }
        case let .array(value):
            var container = encoder.unkeyedContainer()
            for nestedValue in value {
                try container.encode(nestedValue)
            }
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let stream: Bool
    let temperature: Double?
    let topP: Double?
    let topK: Int?
    let maxCompletionTokens: Int?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let reasoningEffort: ModelReasoningEffort?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case topP = "top_p"
        case topK = "top_k"
        case maxCompletionTokens = "max_completion_tokens"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case reasoningEffort = "reasoning_effort"
    }
}

struct OpenAIImageGenerationRequest: Encodable {
    let model: String
    let prompt: String
    let imageCount: Int?
    let size: String?
    let responseFormat: String?
    let outputFormat: String?
    let quality: String?

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case imageCount = "n"
        case size
        case responseFormat = "response_format"
        case outputFormat = "output_format"
        case quality
    }

    static func forDallE(model: String, prompt: String) -> Self {
        OpenAIImageGenerationRequest(
            model: model,
            prompt: prompt,
            imageCount: 1,
            size: "1024x1024",
            responseFormat: "b64_json",
            outputFormat: nil,
            quality: nil
        )
    }

    static func forGPTImage(model: String, prompt: String) -> Self {
        OpenAIImageGenerationRequest(
            model: model,
            prompt: prompt,
            imageCount: nil,
            size: "1024x1024",
            responseFormat: nil,
            outputFormat: "png",
            quality: "auto"
        )
    }
}

struct OpenAIChatMessage: Encodable {
    let role: String
    let content: String
}

struct OpenAIImageGenerationResponse: Decodable {
    let data: [OpenAIImageGenerationData]
}

struct OpenAIImageGenerationData: Codable {
    let b64JSON: String?
    let url: String?
    let revisedPrompt: String?

    enum CodingKeys: String, CodingKey {
        case b64JSON = "b64_json"
        case url
        case revisedPrompt = "revised_prompt"
    }
}

struct OpenAIChatChunk: Decodable {
    let choices: [OpenAIChatChoice]
}

struct OpenAIChatChoice: Decodable {
    let delta: OpenAIChatDelta
}

struct OpenAIChatDelta: Decodable {
    let content: String?
    let role: String?
}

// MARK: - Non-Streaming Chat Completion Response (multimodal)

struct OpenAIChatCompletionResponse: Decodable {
    let choices: [OpenAIChatCompletionChoice]
}

struct OpenAIChatCompletionChoice: Decodable {
    let message: OpenAIChatCompletionMessage
}

struct OpenAIChatCompletionMessage: Decodable {
    let role: String?
    let content: ChatMessageContent
}

/// Chat response `content` can be a plain string or an array of typed parts
/// (text, image_url). Multimodal models like Gemini return image data as parts.
enum ChatMessageContent: Decodable {
    case text(String)
    case parts([ChatContentPart])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        let parts = try container.decode([ChatContentPart].self)
        self = .parts(parts)
    }
}

struct ChatContentPart: Decodable {
    let type: String
    let text: String?
    let imageURL: ChatContentImageURL?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }
}

struct ChatContentImageURL: Decodable {
    let url: String
}
