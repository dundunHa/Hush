import SwiftUI

struct ArchivedThreadsSettingsView: View {
    @EnvironmentObject private var container: AppContainer

    @State private var archivedThreads: [ConversationSidebarThread] = []
    @State private var isLoading = true
    @State private var selectedIds: Set<String> = []
    @State private var isSelectionMode = false
    @State private var showBatchDeleteConfirmation = false
    @State private var showClearAllConfirmation = false

    private var allSelected: Bool {
        !archivedThreads.isEmpty && selectedIds.count == archivedThreads.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                header

                if isLoading {
                    loadingState
                } else if archivedThreads.isEmpty {
                    emptyState
                } else {
                    threadList
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, HushSpacing.xl)
            .padding(.vertical, HushSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            if isSelectionMode && !selectedIds.isEmpty {
                batchToolbar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task { loadArchivedThreads() }
        .alert("Delete Selected Threads", isPresented: $showBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete \(selectedIds.count)", role: .destructive) {
                batchDeleteSelected()
            }
        } message: {
            Text("Permanently delete \(selectedIds.count) thread(s) and all their messages. This cannot be undone.")
        }
        .alert("Clear All Archived Threads", isPresented: $showClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                batchDeleteAll()
            }
        } message: {
            Text(
                "Permanently delete all \(archivedThreads.count) archived thread(s). This cannot be undone."
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Archived Threads")
                .font(HushTypography.pageTitle)

            if !archivedThreads.isEmpty {
                Text("\(archivedThreads.count)")
                    .font(HushTypography.caption)
                    .foregroundStyle(HushColors.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(HushColors.subtleStroke, in: Capsule())
            }

            Spacer()

            if !isLoading && !archivedThreads.isEmpty {
                headerActions
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: HushSpacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelectionMode.toggle()
                    if !isSelectionMode { selectedIds.removeAll() }
                }
            } label: {
                Label(
                    isSelectionMode ? "Done" : "Select",
                    systemImage: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .font(HushTypography.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isSelectionMode ? .blue : nil)

            Button(role: .destructive) {
                showClearAllConfirmation = true
            } label: {
                Label("Clear All", systemImage: "trash")
                    .font(HushTypography.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        HStack {
            Spacer(minLength: 0)
            ProgressView()
                .controlSize(.regular)
            Spacer(minLength: 0)
        }
        .padding(.vertical, HushSpacing.xl)
    }

    private var emptyState: some View {
        VStack(spacing: HushSpacing.md) {
            Image(systemName: "archivebox")
                .font(.system(size: 32))
                .foregroundStyle(HushColors.secondaryText.opacity(0.5))

            Text("No archived threads")
                .font(HushTypography.body)
                .foregroundStyle(HushColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, HushSpacing.xl)
    }

    // MARK: - Thread List

    private var threadList: some View {
        VStack(spacing: 0) {
            if isSelectionMode {
                selectAllRow
                Divider().overlay(HushColors.subtleStroke)
            }

            ForEach(Array(archivedThreads.enumerated()), id: \.element.id) { index, thread in
                ArchivedThreadRow(
                    thread: thread,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedIds.contains(thread.id),
                    onToggleSelection: { toggleSelection(thread.id) },
                    onUnarchive: { unarchiveThread(thread) },
                    onDelete: { deleteThread(thread) }
                )

                if index < archivedThreads.count - 1 {
                    Divider().overlay(HushColors.subtleStroke)
                }
            }
        }
        .cardStyle(
            background: HushColors.cardBackground,
            stroke: HushColors.subtleStroke
        )
    }

    private var selectAllRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if allSelected {
                    selectedIds.removeAll()
                } else {
                    selectedIds = Set(archivedThreads.map(\.id))
                }
            }
        } label: {
            HStack(spacing: HushSpacing.md) {
                Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(allSelected ? Color.blue : HushColors.secondaryText)
                    .contentTransition(.symbolEffect(.replace))

                Text(allSelected ? "Deselect All" : "Select All")
                    .font(HushTypography.body)
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()
            }
            .padding(.horizontal, HushSpacing.lg)
            .padding(.vertical, HushSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Batch Toolbar

    private var batchToolbar: some View {
        HStack(spacing: HushSpacing.md) {
            Text("\(selectedIds.count) selected")
                .font(HushTypography.body)
                .foregroundStyle(.white)

            Spacer()

            Button {
                batchUnarchiveSelected()
            } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
                    .font(HushTypography.captionBold)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive) {
                showBatchDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(HushTypography.captionBold)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
        .padding(.horizontal, HushSpacing.lg)
        .padding(.vertical, HushSpacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius)
                .stroke(HushColors.subtleStroke, lineWidth: 1)
        )
        .padding(.horizontal, HushSpacing.xl)
        .padding(.bottom, HushSpacing.lg)
    }

    // MARK: - Actions

    private func loadArchivedThreads() {
        isLoading = true
        archivedThreads = container.fetchArchivedThreads()
        isLoading = false
    }

    private func toggleSelection(_ id: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedIds.contains(id) {
                selectedIds.remove(id)
            } else {
                selectedIds.insert(id)
            }
        }
    }

    private func unarchiveThread(_ thread: ConversationSidebarThread) {
        container.unarchiveConversation(conversationId: thread.id)
        withAnimation(.easeInOut(duration: 0.25)) {
            archivedThreads.removeAll { $0.id == thread.id }
            selectedIds.remove(thread.id)
        }
    }

    private func deleteThread(_ thread: ConversationSidebarThread) {
        container.deleteConversation(conversationId: thread.id)
        withAnimation(.easeInOut(duration: 0.25)) {
            archivedThreads.removeAll { $0.id == thread.id }
            selectedIds.remove(thread.id)
        }
    }

    private func batchUnarchiveSelected() {
        let ids = selectedIds
        for id in ids {
            container.unarchiveConversation(conversationId: id)
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            archivedThreads.removeAll { ids.contains($0.id) }
            selectedIds.removeAll()
            if archivedThreads.isEmpty { isSelectionMode = false }
        }
    }

    private func batchDeleteSelected() {
        let ids = selectedIds
        for id in ids {
            container.deleteConversation(conversationId: id)
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            archivedThreads.removeAll { ids.contains($0.id) }
            selectedIds.removeAll()
            if archivedThreads.isEmpty { isSelectionMode = false }
        }
    }

    private func batchDeleteAll() {
        for thread in archivedThreads {
            container.deleteConversation(conversationId: thread.id)
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            archivedThreads.removeAll()
            selectedIds.removeAll()
            isSelectionMode = false
        }
    }
}

// MARK: - ArchivedThreadRow

private struct ArchivedThreadRow: View {
    let thread: ConversationSidebarThread
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onUnarchive: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: HushSpacing.md) {
            if isSelectionMode {
                Button { onToggleSelection() } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? Color.blue : HushColors.secondaryText)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(thread.title)
                    .font(HushTypography.body)
                    .lineLimit(1)

                Text(thread.lastActivityAt, style: .date)
                    .font(HushTypography.caption)
                    .foregroundStyle(HushColors.secondaryText)
            }

            Spacer(minLength: 0)

            if !isSelectionMode && isHovered {
                HStack(spacing: HushSpacing.sm) {
                    Button {
                        onUnarchive()
                    } label: {
                        Label("Unarchive", systemImage: "tray.and.arrow.up")
                            .font(HushTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(HushTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .padding(.horizontal, HushSpacing.lg)
        .padding(.vertical, HushSpacing.md)
        .background(
            isSelectionMode && isSelected
                ? Color.blue.opacity(0.08)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode { onToggleSelection() }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .alert("Delete Thread", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This will permanently delete this thread and all its messages.")
        }
    }
}

#if DEBUG

    #Preview("ArchivedThreadsSettingsView — Empty") {
        ArchivedThreadsSettingsView()
            .environmentObject(AppContainer.makePreviewContainer())
    }

#endif
