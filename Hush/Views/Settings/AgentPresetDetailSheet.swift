import SwiftUI

// MARK: - Detail Sheet

extension AgentSettingsView {
    func presetDetailSheet(presetID: String) -> some View {
        VStack(spacing: 0) {
            presetHeader
                .padding(.horizontal, HushSpacing.xl)
                .padding(.top, HushSpacing.xl)
                .padding(.bottom, HushSpacing.lg)

            Divider()
                .foregroundStyle(palette.separator)

            HStack(alignment: .top, spacing: HushSpacing.lg) {
                leftColumn
                    .frame(width: 320)

                Divider()
                    .foregroundStyle(palette.separator)

                rightColumn
                    .frame(minWidth: 280)
            }
            .padding(.horizontal, HushSpacing.xl)
            .padding(.vertical, HushSpacing.lg)

            Spacer(minLength: 0)

            Divider()
                .foregroundStyle(palette.separator)

            actionBar(presetID: presetID)
                .padding(.horizontal, HushSpacing.xl)
                .padding(.vertical, HushSpacing.lg)
        }
        .frame(width: 720, height: 720)
        .background(palette.rootBackground)
    }

    var presetHeader: some View {
        HStack(alignment: .center, spacing: HushSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "person.badge.key")
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)
            }

            TextField("Agent Name", text: $presetName)
                .font(HushTypography.pageTitle)
                .textFieldStyle(.plain)
        }
    }

    // MARK: - Left Column

    var leftColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                providerModelSection
                thinkingSection
                systemPromptSection
            }
        }
    }

    var providerModelSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Label("Provider & Model", systemImage: "cpu")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

                Text("Select an API provider and one of its selected models for this agent.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: HushSpacing.sm) {
                HStack {
                    Text("Provider")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 60, alignment: .leading)

                    Picker("", selection: $selectedProviderID) {
                        Text("None").tag("")
                        ForEach(enabledProviders) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .onChange(of: selectedProviderID) { _, _ in
                        selectedModelID = ""
                    }
                }

                HStack {
                    Text("Model")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 60, alignment: .leading)

                    Picker("", selection: $selectedModelID) {
                        Text("None").tag("")
                        ForEach(availableModels, id: \.self) { modelID in
                            Text(modelID).tag(modelID)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .disabled(selectedProviderID.isEmpty)
                }
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Label("System Prompt", systemImage: "text.quote")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

                Text("Instructions that define this agent's behavior and persona. Sent at the start of every conversation.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextEditor(text: $systemPrompt)
                .font(HushTypography.body)
                .scrollContentBackground(.hidden)
                .padding(HushSpacing.sm)
                .frame(minHeight: 200, maxHeight: 320)
                .background(palette.softFill, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(palette.subtleStroke, lineWidth: 1)
                )
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    var thinkingSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Label("Thinking", systemImage: "brain")
                .font(HushTypography.captionBold)
                .foregroundStyle(palette.secondaryText)

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Thinking Budget")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    TextField("Optional", text: $thinkingBudgetString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Text("Token budget for extended thinking models (e.g. o1, Claude 3.5). Leave empty if not supported.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    // MARK: - Right Column

    var rightColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                generationSection
                samplingSection
                penaltiesSection
            }
        }
    }

    var generationSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Label("Generation", systemImage: "slider.horizontal.3")
                .font(HushTypography.captionBold)
                .foregroundStyle(palette.secondaryText)

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Temperature")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Text(String(format: "%.1f", temperature))
                        .font(HushTypography.monospaced(12))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 2)
                        .background(palette.softFillStrong, in: RoundedRectangle(cornerRadius: 4))
                }
                Slider(value: $temperature, in: 0 ... 2, step: 0.1)
                    .controlSize(.small)
                Text("Controls randomness. Lower values produce more focused output, higher values increase creativity.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Max Tokens")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    TextField("4096", text: $maxTokensString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Text("Maximum number of tokens the model can generate in a single response.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    var samplingSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Label("Sampling", systemImage: "dial.low")
                .font(HushTypography.captionBold)
                .foregroundStyle(palette.secondaryText)

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Top P")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Text(String(format: "%.2f", topP))
                        .font(HushTypography.monospaced(12))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 2)
                        .background(palette.softFillStrong, in: RoundedRectangle(cornerRadius: 4))
                }
                Slider(value: $topP, in: 0 ... 1, step: 0.05)
                    .controlSize(.small)
                Text("Nucleus sampling. Only considers tokens within the top cumulative probability. Use with temperature.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Top K")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    TextField("Optional", text: $topKString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Text("Limits sampling to the K most likely tokens. Leave empty to disable.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    var penaltiesSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Label("Penalties", systemImage: "arrow.triangle.branch")
                .font(HushTypography.captionBold)
                .foregroundStyle(palette.secondaryText)

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Presence Penalty")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Text(String(format: "%.2f", presencePenalty))
                        .font(HushTypography.monospaced(12))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 2)
                        .background(palette.softFillStrong, in: RoundedRectangle(cornerRadius: 4))
                }
                Slider(value: $presencePenalty, in: 0 ... 2, step: 0.05)
                    .controlSize(.small)
                Text("Encourages the model to talk about new topics. Higher values reduce repetition of ideas.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Frequency Penalty")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Text(String(format: "%.2f", frequencyPenalty))
                        .font(HushTypography.monospaced(12))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 2)
                        .background(palette.softFillStrong, in: RoundedRectangle(cornerRadius: 4))
                }
                Slider(value: $frequencyPenalty, in: 0 ... 2, step: 0.05)
                    .controlSize(.small)
                Text("Penalizes tokens based on how often they appear. Higher values discourage word repetition.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }
}
