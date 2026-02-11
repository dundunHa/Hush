import SwiftUI

struct PromptLibraryView: View {
    @EnvironmentObject private var container: AppContainer

    @State private var templates: [PromptTemplate] = []
    @State private var editingTemplateID: String?
    @State private var isCreatingNew: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    @State private var templateName: String = ""
    @State private var templateContent: String = ""
    @State private var templateCategory: String = ""

    var body: some View {
        templateListPane
            .onAppear { refreshTemplates() }
            .sheet(isPresented: Binding(
                get: { editingTemplateID != nil },
                set: { if !$0 { editingTemplateID = nil; isCreatingNew = false } }
            )) {
                if let templateID = editingTemplateID {
                    templateDetailSheet(templateID: templateID)
                }
            }
    }

    // MARK: - Template List

    private var templateListPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                HStack {
                    Text("Prompt Library")
                        .font(HushTypography.pageTitle)

                    Spacer()

                    Button {
                        loadDefaultsForNewTemplate()
                        isCreatingNew = true
                        editingTemplateID = "__new__"
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if templates.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: HushSpacing.sm) {
                        ForEach(templates) { template in
                            templateListRow(template)
                        }
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, HushSpacing.xl)
            .padding(.vertical, HushSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: HushSpacing.md) {
            Image(systemName: "text.quote")
                .font(.system(size: 40))
                .foregroundStyle(HushColors.secondaryText)

            Text("No Prompt Templates")
                .font(HushTypography.heading)

            Text("Create reusable prompt templates for quick access.")
                .font(HushTypography.body)
                .foregroundStyle(HushColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HushSpacing.xl * 2)
    }

    private func templateListRow(_ template: PromptTemplate) -> some View {
        PromptTemplateRow(template: template) {
            loadSnapshotForTemplate(template.id)
            editingTemplateID = template.id
        }
    }

    // MARK: - Detail Sheet

    private func templateDetailSheet(templateID: String) -> some View {
        VStack(spacing: 0) {
            templateHeader
                .padding(.horizontal, HushSpacing.xl)
                .padding(.top, HushSpacing.xl)
                .padding(.bottom, HushSpacing.lg)

            Divider()
                .foregroundStyle(HushColors.separator)

            ScrollView {
                VStack(alignment: .leading, spacing: HushSpacing.lg) {
                    categorySection
                    contentSection
                }
                .padding(.horizontal, HushSpacing.xl)
                .padding(.vertical, HushSpacing.lg)
            }

            Spacer(minLength: 0)

            Divider()
                .foregroundStyle(HushColors.separator)

            actionBar(templateID: templateID)
                .padding(.horizontal, HushSpacing.xl)
                .padding(.vertical, HushSpacing.lg)
        }
        .frame(width: 600, height: 560)
        .background(HushColors.rootBackground)
    }

    private var templateHeader: some View {
        HStack(alignment: .center, spacing: HushSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "text.quote")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
            }

            TextField("Template Name", text: $templateName)
                .font(HushTypography.pageTitle)
                .textFieldStyle(.plain)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Label("Category", systemImage: "folder")
                .font(HushTypography.captionBold)
                .foregroundStyle(HushColors.secondaryText)

            TextField("Optional category", text: $templateCategory)
                .textFieldStyle(.roundedBorder)
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: HushColors.cardBackground,
            stroke: HushColors.subtleStroke
        )
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Label("Prompt Content", systemImage: "text.alignleft")
                .font(HushTypography.captionBold)
                .foregroundStyle(HushColors.secondaryText)

            TextEditor(text: $templateContent)
                .font(HushTypography.body)
                .scrollContentBackground(.hidden)
                .padding(HushSpacing.sm)
                .frame(minHeight: 240, maxHeight: 360)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(HushColors.subtleStroke, lineWidth: 1)
                )
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: HushColors.cardBackground,
            stroke: HushColors.subtleStroke
        )
    }

    // MARK: - Action Bar

    private func actionBar(templateID: String) -> some View {
        HStack(spacing: HushSpacing.md) {
            if !isCreatingNew {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .alert("Delete Prompt Template?", isPresented: $showDeleteConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        container.deletePromptTemplate(id: templateID)
                        editingTemplateID = nil
                        refreshTemplates()
                    }
                } message: {
                    Text("This template will be permanently deleted.")
                }
            }

            Spacer()

            Button("Cancel") {
                editingTemplateID = nil
            }
            .buttonStyle(.bordered)

            Button("Save") {
                saveTemplate(id: templateID)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func refreshTemplates() {
        templates = container.fetchPromptTemplates()
    }

    private func loadDefaultsForNewTemplate() {
        templateName = "New Template"
        templateContent = ""
        templateCategory = ""
    }

    private func loadSnapshotForTemplate(_ templateID: String) {
        guard let template = templates.first(where: { $0.id == templateID }) else { return }
        templateName = template.name
        templateContent = template.content
        templateCategory = template.category
    }

    private func saveTemplate(id: String) {
        let trimmedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? "Untitled Template" : trimmedName
        let category = templateCategory.trimmingCharacters(in: .whitespacesAndNewlines)

        if isCreatingNew {
            let newTemplate = PromptTemplate(
                name: name,
                content: templateContent,
                category: category
            )
            container.savePromptTemplate(newTemplate)
        } else {
            guard let existingTemplate = templates.first(where: { $0.id == id }) else { return }
            let updatedTemplate = PromptTemplate(
                id: id,
                name: name,
                content: templateContent,
                category: category,
                createdAt: existingTemplate.createdAt,
                updatedAt: .now
            )
            container.savePromptTemplate(updatedTemplate)
        }

        isCreatingNew = false
        editingTemplateID = nil
        refreshTemplates()
    }
}

// MARK: - PromptTemplateRow

private struct PromptTemplateRow: View {
    let template: PromptTemplate
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: HushSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(isHovered ? 0.20 : 0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: "text.quote")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(HushTypography.body)
                        .foregroundStyle(.white)
                        .lineLimit(1)

//                    if !template.category.isEmpty {
//                        Text(template.category)
//                            .font(HushTypography.caption)
//                            .foregroundStyle(HushColors.secondaryText)
//                            .lineLimit(1)
//                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        HushColors.secondaryText.opacity(isHovered ? 1.0 : 0.6)
                    )
            }
            .padding(.horizontal, HushSpacing.lg)
            .padding(.vertical, HushSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.06) : HushColors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                            .stroke(
                                isHovered ? Color.white.opacity(0.16) : HushColors.subtleStroke,
                                lineWidth: 1
                            )
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#if DEBUG

    // MARK: - Previews

    #Preview("PromptLibraryView — Empty State") {
        PromptLibraryView()
            .environmentObject(AppContainer.makePreviewContainer())
    }

    #Preview("PromptLibraryView — With Data") {
        PromptLibraryView()
            .environmentObject(AppContainer.makePreviewContainerWithData())
    }

    #Preview("PromptTemplateRow") {
        VStack(spacing: 8) {
            PromptTemplateRow(
                template: PromptTemplate(
                    name: "Code Review",
                    content: "Review this code for best practices",
                    category: "Development"
                ),
                onTap: {}
            )
            PromptTemplateRow(
                template: PromptTemplate(
                    name: "Explain Concept",
                    content: "Explain this concept in simple terms",
                    category: "Education"
                ),
                onTap: {}
            )
        }
        .padding()
    }
#endif
