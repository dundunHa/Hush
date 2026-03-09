import SwiftUI

struct ConversationSidebarView: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            actions
            threadList
            settingsButton
        }
        .background(HushColors.sidebarBackground)
        .frame(maxHeight: .infinity, alignment: .top)
        .themeRefreshAware()
    }

    private var header: some View {
        HStack(spacing: HushSpacing.sm) {
            Label("Chats", systemImage: "bubble.left.and.bubble.right")
                .font(HushTypography.heading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, HushSpacing.md)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: HushSpacing.xs) {
            Button {
                container.resetConversation()
            } label: {
                Label("New thread", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HushSpacing.sm)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, HushSpacing.sm)
        .padding(.vertical, HushSpacing.sm)
        .disabled(false)
    }

    private var threadList: some View {
        VStack(alignment: .leading, spacing: HushSpacing.sm) {
            Text("Threads")
                .font(HushTypography.captionBold)
                .foregroundStyle(HushColors.secondaryText)
                .padding(.horizontal, 14)
                .padding(.top, HushSpacing.sm)

            if container.sidebarThreads.isEmpty {
                Text("No conversation yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, HushSpacing.sm)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: HushSpacing.xs) {
                        ForEach(container.sidebarThreads) { thread in
                            SidebarThreadRow(
                                thread: thread,
                                isActive: container.activeConversationId == thread.id,
                                isDisabled: false,
                                activityState: sidebarActivityState(for: thread.id)
                            ) {
                                container.clearUnreadCompletion(forConversation: thread.id)
                                container.activateConversation(conversationId: thread.id)
                            } onDelete: {
                                container.deleteConversation(conversationId: thread.id)
                            } onArchive: {
                                container.archiveConversation(conversationId: thread.id)
                            }
                        }
                        paginationFooter
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HushSpacing.sm)
                    .padding(.vertical, HushSpacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if container.isLoadingMoreSidebarThreads {
            HStack {
                Spacer(minLength: 0)
                ProgressView()
                    .controlSize(.small)
                Spacer(minLength: 0)
            }
            .padding(.vertical, HushSpacing.sm)
        } else if container.hasMoreSidebarThreads {
            Color.clear
                .frame(height: 1)
                .onAppear {
                    Task {
                        await container.loadMoreSidebarThreadsIfNeeded()
                    }
                }
        } else if !container.sidebarThreads.isEmpty {
            Text("No more threads")
                .font(HushTypography.caption)
                .foregroundStyle(HushColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, HushSpacing.sm)
        }
    }

    private func sidebarActivityState(for conversationId: String) -> SidebarActivityState {
        if container.unreadCompletions.contains(conversationId) {
            return .unreadCompletion
        }
        if container.runningConversationIds.contains(conversationId) {
            return .running
        }
        if let count = container.queuedConversationCounts[conversationId], count > 0 {
            return .queued
        }
        return .idle
    }

    @State private var isSettingsHovered: Bool = false

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HushSpacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSettingsHovered ? HushColors.hoverFill : .clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    isSettingsHovered ? HushColors.hoverStroke : .clear,
                                    lineWidth: 1
                                )
                        )
                        .animation(.easeInOut(duration: 0.15), value: isSettingsHovered)
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            isSettingsHovered = hovering
        }
        .padding(.horizontal, HushSpacing.sm)
        .padding(.bottom, HushSpacing.md)
    }
}

enum SidebarActivityState: Equatable {
    case idle
    case running
    case queued
    case unreadCompletion
}

private struct SidebarThreadRow: View {
    let thread: ConversationSidebarThread
    let isActive: Bool
    let isDisabled: Bool
    let activityState: SidebarActivityState
    let onTap: () -> Void
    let onDelete: () -> Void
    let onArchive: () -> Void

    @State private var isHovered: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var archiveConfirmPending: Bool = false
    @State private var archiveResetTask: Task<Void, Never>?

    private enum ContextAction: CaseIterable, Hashable {
        case archive
        case delete
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: HushSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.title)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(thread.lastActivityAt, style: .time)
                        .font(HushTypography.caption)
                        .foregroundStyle(HushColors.secondaryText)
                }

                trailingAccessory
            }
            .padding(.horizontal, HushSpacing.sm)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contextMenu {
            ForEach(ContextAction.allCases, id: \.self) { action in
                switch action {
                case .archive:
                    Button {
                        onArchive()
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .disabled(isDisabled)
                case .delete:
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(isDisabled)
                }
            }
        }
        .alert("Delete Thread", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This will permanently delete this thread and all its messages.")
        }
        .onHover { hovering in
            isHovered = hovering
            if !hovering {
                resetArchiveConfirmation()
            }
        }
        .onDisappear {
            archiveResetTask?.cancel()
            archiveResetTask = nil
        }
        .disabled(isDisabled)
        .themeRefreshAware()
    }

    private var trailingAccessory: some View {
        ZStack {
            activityBadge
                .opacity(showsActivityBadge ? 1 : 0)

            archiveButton
                .opacity(showsArchiveAction ? 1 : 0)
                .allowsHitTesting(showsArchiveAction)
                .accessibilityHidden(!showsArchiveAction)
        }
        .frame(width: 22, height: 22, alignment: .center)
        .animation(.easeInOut(duration: 0.15), value: showsArchiveAction)
        .animation(.easeInOut(duration: 0.15), value: showsActivityBadge)
    }

    private var showsArchiveAction: Bool {
        isHovered && !isDisabled
    }

    private var showsActivityBadge: Bool {
        activityState != .idle && !showsArchiveAction
    }

    private var archiveButton: some View {
        Button {
            if archiveConfirmPending {
                onArchive()
                resetArchiveConfirmation()
            } else {
                archiveConfirmPending = true
                scheduleArchiveReset()
            }
        } label: {
            Image(systemName: archiveConfirmPending ? "archivebox.fill" : "archivebox")
                .font(.system(size: 13))
                .foregroundStyle(archiveConfirmPending ? HushColors.badgeQueued : HushColors.tertiaryText)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(archiveConfirmPending ? "Click again to archive" : "Archive thread")
    }

    private func scheduleArchiveReset() {
        archiveResetTask?.cancel()
        archiveResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            resetArchiveConfirmation()
        }
    }

    private func resetArchiveConfirmation() {
        archiveConfirmPending = false
        archiveResetTask?.cancel()
        archiveResetTask = nil
    }

    @ViewBuilder
    private var activityBadge: some View {
        switch activityState {
        case .running:
            Circle()
                .fill(HushColors.badgeRunning)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Generating")
        case .queued:
            Circle()
                .fill(HushColors.badgeQueued)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Queued")
        case .unreadCompletion:
            Circle()
                .fill(HushColors.badgeUnread)
                .frame(width: 8, height: 8)
                .accessibilityLabel("New response")
        case .idle:
            EmptyView()
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isActive ? HushColors.selectionFill : (isHovered ? HushColors.hoverFill : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isActive ? HushColors.selectionStroke : (isHovered ? HushColors.hoverStroke : .clear),
                        lineWidth: 1
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

#if DEBUG

    #Preview("ConversationSidebarView — Empty State") {
        ConversationSidebarView(showSettings: .constant(false))
            .environmentObject(
                AppContainer.makePreviewContainer(sidebarThreads: [])
            )
    }

    #Preview("ConversationSidebarView — With Threads") {
        ConversationSidebarView(showSettings: .constant(false))
            .environmentObject(
                AppContainer.makePreviewContainer(
                    activeConversationId: "2",
                    sidebarThreads: [
                        ConversationSidebarThread(id: "1", title: "First conversation", lastActivityAt: Date()),
                        ConversationSidebarThread(
                            id: "2", title: "Second conversation",
                            lastActivityAt: Date().addingTimeInterval(-3600)
                        ),
                        ConversationSidebarThread(
                            id: "3", title: "Third conversation", lastActivityAt: Date().addingTimeInterval(-7200)
                        )
                    ]
                )
            )
    }

#endif
