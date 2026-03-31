import SwiftUI

// MARK: - Detail Pane Views

extension ProviderSettingsView {
    var detailPane: some View {
        Group {
            if let selectedTarget {
                providerDetailPane(target: selectedTarget)
            } else {
                emptyDetailPane
            }
        }
    }

    var emptyDetailPane: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Select a provider")
                .font(HushTypography.heading)
                .foregroundStyle(palette.primaryText)

            Text("Choose a provider from the list or create a new one to configure credentials, models, and defaults.")
                .font(HushTypography.body)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HushSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(detailPaneBackground)
    }

    func providerDetailPane(target: ProviderEditorTarget) -> some View {
        let config = currentEditingConfiguration(for: target)
        let providerID = editorProviderID(for: target)

        return VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: HushSpacing.lg) {
                    providerHeader(config)
                    basicsSection(config)
                    modelsSection(providerID: providerID)
                    advancedSection
                }
                .padding(.horizontal, HushSpacing.xl)
            }
            .contentMargins(.vertical, 32)
            .scrollBounceBehavior(.basedOnSize)

            Divider()
                .foregroundStyle(palette.subtleStroke)

            VStack(spacing: HushSpacing.xs) {
                if !saveMessage.isEmpty {
                    Text(saveMessage)
                        .font(HushTypography.footnote)
                        .foregroundStyle(saveFailed ? palette.errorText : palette.successText)
                }

                actionBar(config)
            }
            .padding(.horizontal, HushSpacing.xl)
            .padding(.vertical, HushSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(detailPaneBackground)
        .alert(Text(deleteConfirmationTitle), isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteCurrentProvider()
            }
        } message: {
            Text("This provider and its cached models will be removed.")
        }
    }

    var detailPaneBackground: some View {
        RoundedRectangle(cornerRadius: ProviderSettingsLayout.paneCornerRadius, style: .continuous)
            .fill(palette.rootBackground)
            .overlay(
                RoundedRectangle(cornerRadius: ProviderSettingsLayout.paneCornerRadius, style: .continuous)
                    .stroke(palette.subtleStroke, lineWidth: 1)
            )
    }

    // MARK: - Header

    func providerHeader(_ config: ProviderConfiguration) -> some View {
        HStack(alignment: .center, spacing: HushSpacing.md) {
            Image(systemName: providerIcon(for: config.type))
                .font(.system(size: 22))
                .foregroundStyle(providerAccent(for: config.type))

            VStack(alignment: .leading, spacing: 6) {
                Text(isBuiltInProvider ? "OpenAI" : (providerName.isEmpty ? "New Provider" : providerName))
                    .font(HushTypography.pageTitle)

                HStack(spacing: HushSpacing.xs) {
                    if isBuiltInProvider {
                        Label("Built-in", systemImage: "lock.fill")
                            .font(HushTypography.caption)
                            .foregroundStyle(palette.secondaryText)
                    }

                    if isCurrentDefault {
                        Text("Default")
                            .font(HushTypography.caption)
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, HushSpacing.sm)
                            .padding(.vertical, 3)
                            .background(palette.accentMutedBackground, in: Capsule())
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Basics Section

    func basicsSection(_ config: ProviderConfiguration) -> some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            HStack(alignment: .center) {
                Text("Basics")
                    .font(HushTypography.heading)
                    .foregroundStyle(palette.secondaryText)

                Spacer()

                Toggle("Enabled", isOn: $isEnabled)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("Title")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

                if isBuiltInProvider {
                    Text(config.name)
                        .font(HushTypography.body)
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, HushSpacing.md)
                        .padding(.vertical, HushSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.softFill)
                        )
                } else {
                    TextField("Provider name", text: $providerName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("Endpoint")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

                TextField(defaultEndpointPlaceholder(for: config.type), text: $endpoint)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("API Key")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

                HStack(spacing: HushSpacing.xs) {
                    if isAPIKeyRevealed {
                        TextField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        isAPIKeyRevealed.toggle()
                    } label: {
                        Image(systemName: isAPIKeyRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(isAPIKeyRevealed ? "Hide" : "Reveal")
                }

                if hasStoredCredential, apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Saved locally. Leave blank to keep the existing key.")
                        .font(HushTypography.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    // MARK: - Models Section

    // swiftlint:disable function_body_length
    func modelsSection(providerID: String) -> some View {
        let hasPersistedProfile = persistedConfig(for: providerID) != nil
        let allModels = visibleCatalogModels(for: providerID)
        let filteredModels = filteredCatalogModels(allModels)
        let selectedModelIDs = selectedCatalogModelIDs(for: allModels)
        let isRefreshing = isCatalogRefreshing(for: providerID)
        let refreshError = visibleCatalogRefreshError(for: providerID)
        let isDraftSource = shouldDisplayDraftCatalog(for: providerID)
        let hasFilteredModels = !filteredModels.isEmpty
        let areAllFilteredModelsSelected = !filteredModels.isEmpty
            && Set(filteredModels.map(\.id)).isSubset(of: Set(selectedModelIDs))
        let defaultModelSelection = catalogDefaultSelection(for: allModels)
        let usingManualDefaultModelID = isUsingManualDefaultModelID(for: allModels)
        let selectedSummary = "\(selectedModelIDs.count) selected / \(allModels.count) available"

        return VStack(alignment: .leading, spacing: HushSpacing.md) {
            HStack {
                Text("Models")
                    .font(HushTypography.heading)
                    .foregroundStyle(palette.secondaryText)

                Spacer()

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    triggerRefreshFromForm(providerID: providerID)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
            }

            VStack(alignment: .leading, spacing: HushSpacing.sm) {
                HStack {
                    Text("Default Model")
                        .font(HushTypography.captionBold)
                        .foregroundStyle(palette.secondaryText)

                    Spacer()

                    Text(selectedSummary)
                        .font(HushTypography.footnote)
                        .foregroundStyle(palette.secondaryText)
                }

                Picker(
                    selectedModelIDs.isEmpty
                        ? "Select models below first"
                        : "Choose a default model",
                    selection: Binding(
                        get: { defaultModelSelection },
                        set: { defaultModelID = $0 }
                    )
                ) {
                    Text(selectedModelIDs.isEmpty ? "Select models below first" : "Choose a default model")
                        .tag("")

                    ForEach(selectedModelIDs, id: \.self) { modelID in
                        Text(modelID).tag(modelID)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(selectedModelIDs.isEmpty)

                if defaultModelSelection.isEmpty, !normalizedDraftDefaultModelID.isEmpty, usingManualDefaultModelID {
                    HStack(spacing: HushSpacing.xs) {
                        Image(systemName: "number.square")
                            .foregroundStyle(palette.secondaryText)
                        Text("Manual default model ID: \(normalizedDraftDefaultModelID)")
                            .font(HushTypography.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                } else if normalizedDraftDefaultModelID.isEmpty {
                    HStack(spacing: HushSpacing.xs) {
                        Image(systemName: isEnabled ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(isEnabled ? palette.errorText : palette.secondaryText)
                        Text(
                            isEnabled
                                ? "Enabled providers need a default model."
                                : "Pick a default model from the selected models or enter one manually in Advanced."
                        )
                        .font(HushTypography.footnote)
                        .foregroundStyle(isEnabled ? palette.errorText : palette.secondaryText)
                    }
                } else {
                    HStack(spacing: HushSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.successText)
                        Text("Default model: \(normalizedDraftDefaultModelID)")
                            .font(HushTypography.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }

            if let refreshError {
                HStack(spacing: HushSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.errorText)
                    Text(refreshError)
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.errorText)
                }
                .padding(.vertical, HushSpacing.xs)
            }

            VStack(alignment: .leading, spacing: HushSpacing.sm) {
                Text("Model Catalog")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

                TextField("Search models...", text: $modelSearchText)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: HushSpacing.sm) {
                    Button(modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Select All" : "Select All Filtered") {
                        selectAllFilteredCatalogModels(filteredModels: filteredModels, allModels: allModels)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasFilteredModels || areAllFilteredModelsSelected)

                    Button("Clear Selection") {
                        clearSelectedCatalogModels(allModels)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedModelIDs.isEmpty)
                }
            }

            if allModels.isEmpty {
                HStack(spacing: HushSpacing.sm) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(palette.secondaryText)
                    Text(
                        isRefreshing
                            ? "Fetching models..."
                            : (isDraftSource
                                ? "No models returned for the current draft. Adjust the basics and refresh again."
                                : (hasPersistedProfile
                                    ? "No models cached. Tap Refresh to fetch."
                                    : "Refresh to fetch models for this draft before saving."))
                    )
                    .font(HushTypography.caption)
                    .foregroundStyle(palette.secondaryText)
                }
                .padding(.vertical, HushSpacing.sm)
            } else {
                VStack(alignment: .leading, spacing: HushSpacing.xs) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredModels) { model in
                                let isSelected = selectedModelIDs.contains(model.id)

                                HStack(spacing: HushSpacing.md) {
                                    Button {
                                        toggleSelectedCatalogModel(model.id, allModels: allModels)
                                    } label: {
                                        HStack(spacing: HushSpacing.md) {
                                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(isSelected ? palette.successText : palette.secondaryText)
                                                .frame(width: 20)

                                            Text(model.id)
                                                .font(HushTypography.body)
                                                .foregroundStyle(palette.primaryText)
                                                .lineLimit(1)

                                            Spacer()

                                            if model.modelType != .unknown {
                                                Text(model.modelType.rawValue)
                                                    .font(HushTypography.caption)
                                                    .foregroundStyle(palette.secondaryText)
                                                    .padding(.horizontal, HushSpacing.sm)
                                                    .padding(.vertical, 2)
                                                    .background(palette.softFillStrong, in: Capsule())
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .help(isSelected ? "Remove from selected models" : "Add to selected models")
                                }
                                .padding(.horizontal, HushSpacing.sm)
                                .padding(.vertical, HushSpacing.xs)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? palette.selectionFill : .clear)
                                )

                                if model.id != filteredModels.last?.id {
                                    Divider()
                                        .foregroundStyle(palette.subtleStroke)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)

                    if filteredModels.isEmpty {
                        Text("No models match the current search.")
                            .font(HushTypography.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .padding(.vertical, HushSpacing.xs)
                    }

                    Text("\(selectedModelIDs.count) selected models · search does not change saved selection")
                        .font(HushTypography.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    // swiftlint:enable function_body_length

    // MARK: - Advanced Section

    var advancedSection: some View {
        DisclosureGroup(isExpanded: $isAdvancedSectionExpanded) {
            VStack(alignment: .leading, spacing: HushSpacing.md) {
                VStack(alignment: .leading, spacing: HushSpacing.xs) {
                    Text("Manual Model ID")
                        .font(HushTypography.captionBold)
                        .foregroundStyle(palette.secondaryText)

                    TextField("model-id", text: $defaultModelID)
                        .textFieldStyle(.roundedBorder)

                    Text(
                        "Use this only when the provider does not expose the default model"
                            + " in the catalog. Typing here overrides the catalog picker."
                    )
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText)
                }
            }
            .padding(.top, HushSpacing.md)
        } label: {
            HStack {
                Text("Advanced")
                    .font(HushTypography.heading)
                    .foregroundStyle(palette.secondaryText)

                Spacer()

                if isUsingManualDefaultModelID(for: visibleCatalogModels(for: editorProviderID(for: selectedTarget ?? .new))) {
                    Text("Manual Default")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }
}
