extension OpenAIProvider {
    static func normalizeOpenAIModel(_ model: OpenAIModel) -> ModelDescriptor {
        let modelType = inferModelType(from: model)
        let (inputs, outputs) = inferModalities(from: model, modelType: modelType)

        return ModelDescriptor(
            id: model.id,
            displayName: model.id,
            capabilities: legacyCapabilities(inputs: inputs, outputs: outputs),
            modelType: modelType,
            supportedInputs: inputs,
            supportedOutputs: outputs,
            rawMetadataJSON: model.rawMetadataJSON
        )
    }

    private static func inferModelType(from model: OpenAIModel) -> ModelType {
        let lowered = model.id.lowercased()
        if lowered.contains("embedding") { return .embedding }
        if supportsOpenAIImageGenerationEndpoint(modelID: model.id) { return .image }
        if lowered.contains("image") { return .image }
        if lowered.contains("tts") || lowered.contains("whisper") || lowered.contains("audio") { return .audio }
        if supportsReasoningEffort(modelID: model.id) { return .reasoning }
        if lowered.contains("gpt") || lowered.contains("chat") { return .chat }
        return .unknown
    }

    private static func legacyCapabilities(
        inputs: [Modality],
        outputs: [Modality]
    ) -> [ModelCapability] {
        var capabilities: [ModelCapability] = []
        if inputs.contains(.text) || outputs.contains(.text) {
            capabilities.append(.text)
        }
        if inputs.contains(.image) || outputs.contains(.image) {
            capabilities.append(.image)
        }
        return capabilities.isEmpty ? [.text] : capabilities
    }

    static func supportsOpenAIImageGenerationEndpoint(modelID: String) -> Bool {
        let lowered = modelID.lowercased()
        return lowered.hasPrefix("gpt-image")
            || lowered.hasPrefix("dall-e")
            || lowered.hasPrefix("imagen-")
    }

    static func reasoningEffort(
        for modelID: String,
        parameters: ModelParameters
    ) -> ModelReasoningEffort? {
        guard supportsReasoningEffort(modelID: modelID) else { return nil }
        return parameters.reasoningEffort
    }

    private static func supportsReasoningEffort(modelID: String) -> Bool {
        let lowered = modelID.lowercased()
        return lowered.hasPrefix("o1")
            || lowered.hasPrefix("o3")
            || lowered.hasPrefix("o4")
            || lowered.hasPrefix("gpt-5")
    }

    private static func inferModalities(
        from model: OpenAIModel,
        modelType: ModelType
    ) -> (inputs: [Modality], outputs: [Modality]) {
        let lowered = model.id.lowercased()

        switch modelType {
        case .embedding:
            return ([.text], [.text])
        case .image:
            return ([.text], [.image])
        case .audio:
            if lowered.contains("tts") {
                return ([.text], [.audio])
            }
            if lowered.contains("whisper") {
                return ([.audio], [.text])
            }
            return ([.audio, .text], [.audio, .text])
        case .chat, .reasoning:
            if lowered.contains("vision") || lowered.contains("4o") || lowered.contains("4-turbo") {
                return ([.text, .image], [.text])
            }
            return ([.text], [.text])
        case .unknown:
            return ([.text], [.text])
        }
    }
}
