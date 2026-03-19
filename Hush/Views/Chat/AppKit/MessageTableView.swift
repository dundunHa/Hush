import AppKit
import Combine
import SwiftUI

// swiftlint:disable file_length type_body_length

private struct ScrollAnchor {
    let messageID: UUID
    let offsetInRow: CGFloat
}

@MainActor
private final class HorizontalLockedClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        constrained.origin.x = 0
        return constrained
    }
}

@MainActor
private final class VerticalOnlyScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let verticalMagnitude = abs(event.scrollingDeltaY)
        let horizontalMagnitude = abs(event.scrollingDeltaX)
        guard verticalMagnitude >= horizontalMagnitude else { return }
        super.scrollWheel(with: event)
    }

    override func swipe(with _: NSEvent) {}

    override func magnify(with _: NSEvent) {}

    override func rotate(with _: NSEvent) {}

    override func smartMagnify(with _: NSEvent) {}
}

@MainActor
private final class MessageActionOverlayButton: NSButton {
    var themePalette: HushThemePalette = HushColors.palette(for: .dark) {
        didSet { updateVisualState() }
    }

    private var resetTask: Task<Void, Never>?
    private var isHovered = false
    private var isCopied = false
    private var trackingArea: NSTrackingArea?

    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
    private let defaultImage: NSImage
    private let copiedImage: NSImage
    private let defaultToolTip: String
    private let copiedToolTip: String

    init(
        frame frameRect: NSRect,
        defaultSymbolName: String,
        copiedSymbolName: String = "checkmark",
        defaultToolTip: String,
        copiedToolTip: String
    ) {
        defaultImage = Self.makeSymbol(named: defaultSymbolName, description: defaultToolTip)
        copiedImage = Self.makeSymbol(named: copiedSymbolName, description: copiedToolTip)
        self.defaultToolTip = defaultToolTip
        self.copiedToolTip = copiedToolTip
        super.init(frame: frameRect)

        isBordered = false
        bezelStyle = .shadowlessSquare
        image = defaultImage
        imagePosition = .imageOnly
        toolTip = defaultToolTip
        focusRingType = .none

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.masksToBounds = true

        updateVisualState()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    deinit {
        resetTask?.cancel()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateVisualState()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateVisualState()
    }

    func resetState() {
        resetTask?.cancel()
        resetTask = nil
        isCopied = false
        isHovered = false
        updateVisualState()
    }

    func flashCopied() {
        resetTask?.cancel()
        isCopied = true
        updateVisualState()

        resetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, !Task.isCancelled else { return }
            self.isCopied = false
            self.updateVisualState()
        }
    }

    private func updateVisualState() {
        image = isCopied ? copiedImage : defaultImage
        toolTip = isCopied ? copiedToolTip : defaultToolTip
        contentTintColor = isCopied
            ? NSColor(themePalette.successText)
            : (isHovered ? NSColor(themePalette.controlForeground) : NSColor(themePalette.controlForegroundMuted))
        layer?.backgroundColor = NSColor(isHovered ? themePalette.hoverFill : themePalette.softFillStrong).cgColor
        layer?.borderColor = NSColor(isHovered ? themePalette.hoverStroke : themePalette.subtleStroke).cgColor
    }

    private static func makeSymbol(named name: String, description: String) -> NSImage {
        NSImage(
            systemSymbolName: name,
            accessibilityDescription: description
        )?.withSymbolConfiguration(symbolConfiguration) ?? NSImage()
    }
}

@MainActor
final class MessageTableView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    struct RowModel {
        let message: ChatMessage
        let isStreaming: Bool
        let renderHint: MessageRenderHint
    }

    private enum ApplyUpdateMode: Equatable {
        case fullReload
        case appendInsert(startIndex: Int, count: Int)
        case streamingRefresh(row: Int)
        case noOp
    }

    #if DEBUG
        enum UpdateModeForTesting: Equatable {
            case fullReload
            case appendInsert(insertedCount: Int)
            case streamingRefresh(row: Int)
            case noOp
        }
    #endif

    private let scrollView = VerticalOnlyScrollView()
    let tableView = NSTableView()

    var rows: [RowModel] = []
    private var runtime: MessageRenderRuntime?
    private weak var container: AppContainer?
    private var theme: AppTheme = .dark
    private var fontSettings: AppFontSettings = .default
    private var lastGeneration: UInt64?
    private var tailFollowState = TailFollowState()
    private let tailFollowConfig = TailFollowConfig()
    private var boundsChangeObserver: NSObjectProtocol?
    private var liveScrollStartObserver: NSObjectProtocol?
    private var liveScrollEndObserver: NSObjectProtocol?
    private var isLiveScrolling = false
    private var liveScrollFallbackTimer: Timer?
    private var scrollActivityDebounceTask: Task<Void, Never>?
    private var lastScrollOriginY: CGFloat = 0
    private var pendingScrollAnchorRestore: ScrollAnchor?
    private var isScrollAnchorRestoreScheduled = false
    private var pendingPinnedRowHeightInvalidations = IndexSet()
    private var pendingRowHeightInvalidations = IndexSet()
    private var isRowHeightInvalidationFlushScheduled = false
    private var lastScrollToBottomRequestAt: Date = .distantPast
    private var pendingScrollToBottomTask: Task<Void, Never>?

    private enum ScrollDirection: Equatable {
        case up
        case down
        case none
    }

    private var lastScrollDirection: ScrollDirection = .none
    private var lastOlderLoadTriggerAt: Date = .distantPast
    private var lastKnownFirstMessageID: UUID?
    private var lastIsActiveConversationSending = false
    var lastStreamingHeight: CGFloat = 0
    var lastStreamingHeightMeasureAt: Date = .distantPast
    private var lastLayoutHeight: CGFloat = 0
    private var pendingShrinkScroll = false
    private let olderLoadThrottleInterval: TimeInterval = 0.3
    private let lookaheadPrewarmWindow = 6
    private let lookaheadPrewarmMaxBatch = 4
    private var lookaheadPrewarmTask: Task<Void, Never>?
    private var scrollEndPrewarmDebounceTask: Task<Void, Never>?
    private var lastLookaheadPrewarmIDs: [UUID] = []
    #if DEBUG
        // swiftlint:disable identifier_name
        private(set) var lastUpdateModeForTesting: UpdateModeForTesting = .fullReload
        private(set) var lastLookaheadPrewarmIDsForTesting: [UUID] = []
        private(set) var lookaheadScheduleInvocationCountForTesting = 0
        var heightInvalidationCountForTesting = 0
        var scrollToBottomCountForTesting = 0
        var scrollAnchorRestoreCountForTesting = 0
        // swiftlint:enable identifier_name
    #endif

    private var palette: HushThemePalette {
        HushColors.palette(for: theme)
    }

    private var renderStyle: RenderStyle {
        RenderStyle.fromPalette(palette, fontSettings: fontSettings)
    }

    var userHasScrolledUp: Bool {
        get { !tailFollowState.isFollowingTail }
        set { tailFollowState.isFollowingTail = !newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        let clipView = HorizontalLockedClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAutomaticRowHeights = true
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: HushSpacing.sm)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: HushSpacing.lg, right: 0)
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsChangeObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] (_: Notification) in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleBoundsDidChange()
            }
        }

        liveScrollStartObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] (_: Notification) in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleWillStartLiveScroll()
            }
        }

        liveScrollEndObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] (_: Notification) in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleDidEndLiveScroll()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    deinit {
        if let boundsChangeObserver {
            NotificationCenter.default.removeObserver(boundsChangeObserver)
        }
        if let liveScrollStartObserver {
            NotificationCenter.default.removeObserver(liveScrollStartObserver)
        }
        if let liveScrollEndObserver {
            NotificationCenter.default.removeObserver(liveScrollEndObserver)
        }
        liveScrollFallbackTimer?.invalidate()
        liveScrollFallbackTimer = nil
        scrollActivityDebounceTask?.cancel()
        scrollActivityDebounceTask = nil
        lookaheadPrewarmTask?.cancel()
        lookaheadPrewarmTask = nil
        scrollEndPrewarmDebounceTask?.cancel()
        scrollEndPrewarmDebounceTask = nil
        pendingScrollToBottomTask?.cancel()
        pendingScrollToBottomTask = nil

        // Be explicit about breaking AppKit delegate/dataSource links during teardown.
        // In fast unit-test window lifecycles, this avoids callbacks during NSTableView
        // deallocation targeting already-torn-down objects.
        tableView.dataSource = nil
        tableView.delegate = nil
        scrollView.documentView = nil
    }

    override func layout() {
        super.layout()
        guard tableView.numberOfColumns > 0 else { return }
        let targetWidth = max(1, bounds.width.rounded(.down))
        let currentWidth = tableView.tableColumns[0].width
        if abs(currentWidth - targetWidth) > 0.5 {
            tableView.tableColumns[0].width = targetWidth
        }

        let newHeight = bounds.height
        defer { lastLayoutHeight = newHeight }

        // When the view shrinks (e.g. composer dock expanded) while tail-follow
        // is active, defer re-scroll to the next runloop iteration so the clip
        // view geometry has settled. Coalesce multiple shrink events per cycle.
        if lastLayoutHeight > 0, newHeight < lastLayoutHeight,
           !userHasScrolledUp, !rows.isEmpty, !pendingShrinkScroll
        {
            pendingShrinkScroll = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pendingShrinkScroll else { return }
                self.pendingShrinkScroll = false
                guard !self.userHasScrolledUp, !self.rows.isEmpty else { return }
                self.performScrollToBottom(animated: false, reason: .resizeShrink)
                #if DEBUG
                    self.scrollToBottomCountForTesting += 1
                #endif
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_parameter_count function_body_length
    func apply(
        messages: [ChatMessage],
        activeConversationID: String?,
        isActiveConversationSending: Bool,
        switchGeneration: UInt64,
        theme: AppTheme,
        runtime: MessageRenderRuntime,
        container: AppContainer,
        forceFullReload: Bool = false
    ) {
        self.runtime = runtime
        self.container = container
        self.theme = theme
        fontSettings = container.settings.fontSettings

        let previousRows = rows
        let oldCount = previousRows.count
        let newCount = messages.count
        let currentFirstMessageID = messages.first?.id
        let didPrependOlder =
            lastKnownFirstMessageID != nil
                && currentFirstMessageID != nil
                && lastKnownFirstMessageID != currentFirstMessageID
                && newCount > oldCount

        let prependAnchor = didPrependOlder && userHasScrolledUp
            ? captureScrollAnchor(rowModels: previousRows)
            : nil

        updateStreamingState(isSending: isActiveConversationSending)

        let rankByID = makeRankByMessageID(messages)
        let latestID = messages.last?.id
        let newRows = messages.map { message in
            RowModel(
                message: message,
                isStreaming: isActiveConversationSending && message.role == .assistant && message.id == latestID,
                renderHint: MessageRenderHint(
                    conversationID: activeConversationID ?? "__unknown__",
                    messageID: message.id,
                    rankFromLatest: rankByID[message.id] ?? Int.max,
                    isVisible: true,
                    switchGeneration: switchGeneration
                )
            )
        }

        let generationChanged = lastGeneration != switchGeneration
        if generationChanged {
            if isLiveScrolling {
                setLiveScrolling(false)
            } else {
                runtime.setLiveScrolling(false)
            }
            invalidateLiveScrollFallbackTimer()
            scrollActivityDebounceTask?.cancel()
            scrollActivityDebounceTask = nil
            scrollEndPrewarmDebounceTask?.cancel()
            scrollEndPrewarmDebounceTask = nil
            lookaheadPrewarmTask?.cancel()
            lookaheadPrewarmTask = nil
            lastLookaheadPrewarmIDs = []
            pendingPinnedRowHeightInvalidations = []
            pendingScrollAnchorRestore = nil
            isScrollAnchorRestoreScheduled = false
            #if DEBUG
                lastLookaheadPrewarmIDsForTesting = []
            #endif
        }
        let updateMode = resolveUpdateMode(
            previousRows: previousRows,
            newRows: newRows,
            generationChanged: generationChanged,
            didPrependOlder: didPrependOlder,
            forceFullReload: forceFullReload
        )
        rows = newRows

        PerfTrace.count(PerfTrace.Event.visibleRecompute)
        applyTableUpdate(mode: updateMode)
        #if DEBUG
            lastUpdateModeForTesting = testingUpdateMode(from: updateMode)
        #endif

        if didPrependOlder {
            if let prependAnchor {
                restoreScroll(anchor: prependAnchor)
            } else if !userHasScrolledUp {
                scrollToBottom()
            }
        }

        let assistantMessages = messages.filter { $0.role == .assistant }
        if !assistantMessages.isEmpty {
            let targetAssistants = assistantMessages.suffix(RenderConstants.switchPriorityRenderCount)
            if !targetAssistants.isEmpty {
                let style = renderStyle
                let availableWidth = effectiveAvailableWidth()
                let contentWidth = max(1, availableWidth - HushSpacing.xl * 2)
                var hits = 0
                var misses = 0
                for message in targetAssistants {
                    let input = MessageRenderInput(
                        content: message.content,
                        availableWidth: contentWidth,
                        style: style,
                        isStreaming: false
                    )
                    if runtime.cachedOutput(for: input) != nil {
                        hits += 1
                    } else {
                        misses += 1
                    }
                }
                container.reportSwitchPresentedRenderedFromReloadIfNeeded(
                    conversationId: activeConversationID,
                    generation: switchGeneration,
                    renderCacheHits: hits,
                    renderCacheMisses: misses,
                    contentWidth: Int(contentWidth.rounded(.down))
                )
            }
        }

        lastGeneration = switchGeneration
        if generationChanged {
            _ = TailFollow.reduce(
                state: &tailFollowState,
                event: .conversationSwitched,
                config: tailFollowConfig,
                now: .now
            )

            if !messages.isEmpty {
                let action = TailFollow.reduce(
                    state: &tailFollowState,
                    event: .messageAdded(
                        role: messages.last?.role ?? .system,
                        didPrependOlder: false
                    ),
                    config: tailFollowConfig,
                    now: .now
                )
                handleTailFollowAction(action)
            }
        } else if isActiveConversationSending, !userHasScrolledUp, newCount == oldCount {
            performScrollToBottom(animated: false, reason: .streamingContent)
        }

        if !generationChanged, newCount > oldCount {
            let action = TailFollow.reduce(
                state: &tailFollowState,
                event: .messageAdded(
                    role: messages.last?.role ?? .system,
                    didPrependOlder: didPrependOlder
                ),
                config: tailFollowConfig,
                now: .now
            )
            handleTailFollowAction(action)
        }

        lastKnownFirstMessageID = currentFirstMessageID
    }

    func numberOfRows(in _: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < rows.count else { return nil }
        guard tableColumn != nil else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("MessageTableCellView")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? MessageTableCellView)
            ?? MessageTableCellView(identifier: identifier)

        if let runtime {
            let availableWidth = effectiveAvailableWidth()
            cell.configure(
                row: rows[row],
                runtime: runtime,
                availableWidth: availableWidth,
                theme: theme,
                container: container,
                owningTableView: tableView,
                rowIndex: row,
                messageTableView: self
            )
        }
        return cell
    }

    private func resolveUpdateMode(
        previousRows: [RowModel],
        newRows: [RowModel],
        generationChanged: Bool,
        didPrependOlder: Bool,
        forceFullReload: Bool
    ) -> ApplyUpdateMode {
        guard !forceFullReload else { return .fullReload }
        guard !generationChanged else { return .fullReload }
        guard !didPrependOlder else { return .fullReload }

        let oldCount = previousRows.count
        let newCount = newRows.count

        if newCount < oldCount {
            return .fullReload
        }

        if newCount == oldCount {
            return resolveSameCountUpdate(previousRows: previousRows, newRows: newRows)
        }

        // newCount > oldCount
        guard oldCount > 0 else { return .fullReload }
        let oldPrefix = newRows.prefix(oldCount)
        let isSafeAppend = zip(previousRows, oldPrefix).allSatisfy { lhs, rhs in
            lhs.message.id == rhs.message.id
        }
        guard isSafeAppend else { return .fullReload }

        return .appendInsert(startIndex: oldCount, count: newCount - oldCount)
    }

    private func resolveSameCountUpdate(
        previousRows: [RowModel],
        newRows: [RowModel]
    ) -> ApplyUpdateMode {
        let count = newRows.count
        guard count > 0 else { return .fullReload }

        let stableIDs = zip(previousRows, newRows).allSatisfy { lhs, rhs in
            lhs.message.id == rhs.message.id
        }
        guard stableIDs else { return .fullReload }

        let debugInfoChangedRows = zip(previousRows, newRows).enumerated().compactMap { index, pair in
            pair.0.message.debugInfoJSON != pair.1.message.debugInfoJSON ? index : nil
        }
        if debugInfoChangedRows.count == 1, let singleDebugInfoChangedRow = debugInfoChangedRows.first {
            return .streamingRefresh(row: singleDebugInfoChangedRow)
        }
        if !debugInfoChangedRows.isEmpty {
            return .fullReload
        }

        let oldLast = previousRows[count - 1]
        let newLast = newRows[count - 1]
        let wasOrIsStreaming = oldLast.isStreaming || newLast.isStreaming
        if oldLast.message.id == newLast.message.id,
           oldLast.message.attachments != newLast.message.attachments
        {
            return .streamingRefresh(row: count - 1)
        }
        if wasOrIsStreaming,
           oldLast.message.id == newLast.message.id,
           oldLast.message.content != newLast.message.content
           || oldLast.isStreaming != newLast.isStreaming
        {
            return .streamingRefresh(row: count - 1)
        }

        return .noOp
    }

    private func applyTableUpdate(mode: ApplyUpdateMode) {
        switch mode {
        case .fullReload:
            tableView.reloadData()
        case let .appendInsert(startIndex, count):
            guard count > 0 else { return }
            let inserted = IndexSet(integersIn: startIndex ..< (startIndex + count))
            tableView.beginUpdates()
            tableView.insertRows(at: inserted, withAnimation: [])
            tableView.endUpdates()
        case let .streamingRefresh(row):
            guard row >= 0 else {
                tableView.reloadData()
                return
            }
            guard row < rows.count else {
                tableView.reloadData()
                return
            }
            guard tableView.numberOfColumns > 0 else {
                tableView.reloadData()
                return
            }
            tableView.reloadData(
                forRowIndexes: IndexSet(integer: row),
                columnIndexes: IndexSet(integer: 0)
            )
        case .noOp:
            break
        }
    }

    #if DEBUG
        private func testingUpdateMode(from mode: ApplyUpdateMode) -> UpdateModeForTesting {
            switch mode {
            case .fullReload:
                .fullReload
            case let .appendInsert(_, count):
                .appendInsert(insertedCount: count)
            case let .streamingRefresh(row):
                .streamingRefresh(row: row)
            case .noOp:
                .noOp
            }
        }
    #endif

    private func performScrollToBottom(animated: Bool, reason: ScrollReason) {
        _ = TailFollow.reduce(
            state: &tailFollowState,
            event: .programmaticScrollInitiated,
            config: tailFollowConfig,
            now: .now
        )

        let reasonString = switch reason {
        case .switchLoad:
            "switch"
        case .newUser:
            "user-message"
        case .newAssistant:
            "new-assistant"
        case .streamingContent:
            "streaming-content"
        case .streamingFinished:
            "streaming-finished"
        case .resizeShrink:
            "resize-shrink"
        }

        let isDuringStreaming = reason == .streamingContent || reason == .streamingFinished
        PerfTrace.count(
            PerfTrace.Event.scrollAdjustToBottom,
            fields: [
                "during_streaming": isDuringStreaming ? "true" : "false",
                "suppressed": "false",
                "reason": reasonString
            ]
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                scrollToBottom()
            }
        } else {
            scrollToBottom()
        }
    }

    private func updatePinnedState() {
        let clipView = scrollView.contentView
        let docHeight = scrollView.documentView?.frame.height ?? 0
        let visibleMaxY = clipView.bounds.origin.y + clipView.bounds.height
        let distanceFromBottom = max(0, docHeight - visibleMaxY)

        let action = TailFollow.reduce(
            state: &tailFollowState,
            event: .distanceChanged(distanceFromBottom),
            config: tailFollowConfig,
            now: .now
        )

        handleTailFollowAction(action)

        let distanceFromTop = max(0, clipView.bounds.origin.y)
        if distanceFromTop < 200 {
            triggerOlderMessagesLoadIfNeeded()
        }

        guard !isLiveScrolling else { return }
        scheduleLookaheadPrewarm(visibleRows: tableView.rows(in: tableView.visibleRect))
    }

    private func handleBoundsDidChange() {
        let originY = scrollView.contentView.bounds.origin.y
        trackScrollActivity(originY: originY)
        updatePinnedState()
    }

    private func trackScrollActivity(originY: CGFloat) {
        let delta = originY - lastScrollOriginY
        defer { lastScrollOriginY = originY }

        guard abs(delta) > 0.5 else { return }
        lastScrollDirection = delta > 0 ? .down : .up

        if !isLiveScrolling {
            beginScrollActivity()
        }

        scrollActivityDebounceTask?.cancel()
        scrollActivityDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.endScrollActivity()
        }
    }

    private func handleWillStartLiveScroll() {
        beginScrollActivity()
        resetLiveScrollFallbackTimer()
    }

    private func handleDidEndLiveScroll() {
        invalidateLiveScrollFallbackTimer()
        scrollActivityDebounceTask?.cancel()
        scrollActivityDebounceTask = nil
        endScrollActivity()
    }

    private func beginScrollActivity() {
        scrollEndPrewarmDebounceTask?.cancel()
        scrollEndPrewarmDebounceTask = nil
        lookaheadPrewarmTask?.cancel()
        lookaheadPrewarmTask = nil
        setLiveScrolling(true)
        container?.cancelIdlePrewarmFromCoordinator()
    }

    private func endScrollActivity() {
        guard isLiveScrolling else { return }
        setLiveScrolling(false)
        flushPinnedRowHeightInvalidationsIfNeeded()
        flushPendingScrollAnchorRestoreIfNeeded()
        scheduleScrollEndDebouncedPrewarm()
        container?.scheduleIdlePrewarmFromCoordinator()
    }

    private func setLiveScrolling(_ value: Bool) {
        guard isLiveScrolling != value else { return }
        isLiveScrolling = value
        runtime?.setLiveScrolling(value)
    }

    private func flushPendingScrollAnchorRestoreIfNeeded() {
        guard !isLiveScrolling else { return }
        guard userHasScrolledUp else {
            pendingScrollAnchorRestore = nil
            return
        }
        guard let pendingAnchor = pendingScrollAnchorRestore else { return }
        pendingScrollAnchorRestore = nil

        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.length > 0 else { return }
        guard visibleRows.location != NSNotFound else { return }
        guard visibleRows.location >= 0, visibleRows.location < rows.count else { return }
        guard rows[visibleRows.location].message.id == pendingAnchor.messageID else { return }

        guard let pendingIndex = rows.firstIndex(where: { $0.message.id == pendingAnchor.messageID }) else { return }
        let pendingRect = tableView.rect(ofRow: pendingIndex)
        let desiredY = pendingRect.origin.y + pendingAnchor.offsetInRow
        let currentY = scrollView.contentView.bounds.origin.y
        guard abs(currentY - desiredY) > 1.0 else { return }

        restoreScroll(anchor: pendingAnchor)
    }

    fileprivate var shouldDeferPinnedRowHeightInvalidation: Bool {
        userHasScrolledUp && isLiveScrolling
    }

    fileprivate func enqueuePinnedRowHeightInvalidation(rowIndex: Int) {
        pendingPinnedRowHeightInvalidations.insert(rowIndex)
    }

    func requestRowHeightInvalidation(rowIndex: Int) {
        guard rowIndex >= 0 else { return }

        if isLiveScrolling {
            enqueuePinnedRowHeightInvalidation(rowIndex: rowIndex)
            return
        }

        pendingRowHeightInvalidations.insert(rowIndex)
        scheduleRowHeightInvalidationFlushIfNeeded()
    }

    private func scheduleRowHeightInvalidationFlushIfNeeded() {
        guard !pendingRowHeightInvalidations.isEmpty else { return }
        guard !isRowHeightInvalidationFlushScheduled else { return }
        isRowHeightInvalidationFlushScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRowHeightInvalidationFlushScheduled = false
            self.flushRowHeightInvalidationsIfNeeded()
        }
    }

    private func flushRowHeightInvalidationsIfNeeded() {
        guard !pendingRowHeightInvalidations.isEmpty else { return }
        guard !isLiveScrolling else {
            pendingPinnedRowHeightInvalidations.formUnion(pendingRowHeightInvalidations)
            pendingRowHeightInvalidations = []
            return
        }

        let invalidated = pendingRowHeightInvalidations
        pendingRowHeightInvalidations = []

        let anchor = userHasScrolledUp ? captureScrollAnchor(rowModels: rows) : nil
        tableView.noteHeightOfRows(withIndexesChanged: invalidated)
        if let anchor {
            scheduleScrollAnchorRestore(anchor)
        }

        if !userHasScrolledUp, !rows.isEmpty, invalidated.contains(rows.count - 1) {
            requestCoalescedScrollToBottom()
        }
    }

    private func flushPinnedRowHeightInvalidationsIfNeeded() {
        guard !pendingPinnedRowHeightInvalidations.isEmpty else { return }

        let invalidated = pendingPinnedRowHeightInvalidations
        pendingPinnedRowHeightInvalidations = []

        let anchor = userHasScrolledUp ? captureScrollAnchor(rowModels: rows) : nil
        tableView.noteHeightOfRows(withIndexesChanged: invalidated)
        if let anchor {
            scheduleScrollAnchorRestore(anchor)
        }

        if !userHasScrolledUp, !rows.isEmpty, invalidated.contains(rows.count - 1) {
            requestCoalescedScrollToBottom()
        }
    }

    private func scheduleScrollEndDebouncedPrewarm() {
        scrollEndPrewarmDebounceTask?.cancel()
        scrollEndPrewarmDebounceTask = Task { [weak self] in
            let delayNs = UInt64(RenderConstants.scrollEndPrewarmDebounce * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled, let self else { return }
            guard !self.isLiveScrolling else { return }
            let visibleRows = self.tableView.rows(in: self.tableView.visibleRect)
            self.scheduleLookaheadPrewarm(visibleRows: visibleRows)
        }
    }

    private func resetLiveScrollFallbackTimer() {
        invalidateLiveScrollFallbackTimer()
        let timer = Timer(
            timeInterval: RenderConstants.liveScrollFallbackTimeout,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard self.isLiveScrolling else { return }
                self.setLiveScrolling(false)
            }
        }
        liveScrollFallbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func invalidateLiveScrollFallbackTimer() {
        liveScrollFallbackTimer?.invalidate()
        liveScrollFallbackTimer = nil
    }

    private func updateStreamingState(isSending: Bool) {
        if !lastIsActiveConversationSending, isSending {
            _ = TailFollow.reduce(
                state: &tailFollowState,
                event: .streamingStarted,
                config: tailFollowConfig,
                now: .now
            )
        } else if lastIsActiveConversationSending, !isSending {
            let action = TailFollow.reduce(
                state: &tailFollowState,
                event: .streamingCompleted,
                config: tailFollowConfig,
                now: .now
            )
            handleTailFollowAction(action)
        }
        lastIsActiveConversationSending = isSending
    }

    private func handleTailFollowAction(_ action: TailFollowAction) {
        switch action {
        case let .scrollToBottom(animated, reason):
            performScrollToBottom(animated: animated, reason: reason)
        case .none:
            break
        }
    }

    func scrollToBottom() {
        guard !rows.isEmpty else { return }
        tableView.scrollRowToVisible(rows.count - 1)
    }

    func requestCoalescedScrollToBottom() {
        guard !rows.isEmpty else { return }
        guard !userHasScrolledUp else { return }

        let now = Date.now
        let interval = RenderConstants.streamingScrollCoalesceInterval
        let elapsed = now.timeIntervalSince(lastScrollToBottomRequestAt)

        if elapsed >= interval {
            lastScrollToBottomRequestAt = now
            performCoalescedScrollToBottom()
            return
        }

        guard pendingScrollToBottomTask == nil else { return }
        let delay = max(0, interval - elapsed)
        pendingScrollToBottomTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self.pendingScrollToBottomTask = nil

            guard !self.userHasScrolledUp else { return }
            guard !self.rows.isEmpty else { return }

            self.lastScrollToBottomRequestAt = Date.now
            self.performCoalescedScrollToBottom()
        }
    }

    private func performCoalescedScrollToBottom() {
        scrollToBottom()
    }

    private func setScrollOriginY(_ y: CGFloat) {
        guard let documentView = scrollView.documentView else { return }
        let maxY = max(0, documentView.frame.height - scrollView.contentView.bounds.height)
        let target = NSPoint(
            x: 0,
            y: min(max(0, y), maxY)
        )
        scrollView.contentView.scroll(to: target)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    fileprivate func captureScrollAnchor(rowModels: [RowModel]) -> ScrollAnchor? {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.length > 0 else { return nil }
        guard visibleRows.location != NSNotFound else { return nil }

        let anchorRowIndex = visibleRows.location
        guard anchorRowIndex >= 0, anchorRowIndex < rowModels.count else { return nil }

        let rowRect = tableView.rect(ofRow: anchorRowIndex)
        let offsetInRow = scrollView.contentView.bounds.origin.y - rowRect.origin.y
        return ScrollAnchor(
            messageID: rowModels[anchorRowIndex].message.id,
            offsetInRow: offsetInRow
        )
    }

    // swiftlint:disable:next cyclomatic_complexity
    fileprivate func scheduleScrollAnchorRestore(_ anchor: ScrollAnchor) {
        guard userHasScrolledUp else { return }

        // Restore immediately after `noteHeightOfRows` so AppKit doesn't get a chance
        // to paint an intermediate scroll position (visible as a "jitter" jump).
        restoreScroll(anchor: anchor)

        // AppKit can still apply late layout adjustments after row-height changes.
        // Coalesce a settle-check to the next runloop and only re-apply if there's
        // meaningful drift and the user hasn't scrolled away.
        pendingScrollAnchorRestore = anchor
        guard !isScrollAnchorRestoreScheduled else { return }
        isScrollAnchorRestoreScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isScrollAnchorRestoreScheduled = false

            guard self.userHasScrolledUp else {
                self.pendingScrollAnchorRestore = nil
                return
            }
            guard !self.isLiveScrolling else { return }

            guard let pendingAnchor = self.pendingScrollAnchorRestore else { return }
            self.pendingScrollAnchorRestore = nil

            let visibleRows = self.tableView.rows(in: self.tableView.visibleRect)
            guard visibleRows.length > 0 else { return }
            guard visibleRows.location != NSNotFound else { return }
            guard visibleRows.location >= 0, visibleRows.location < self.rows.count else { return }
            guard self.rows[visibleRows.location].message.id == pendingAnchor.messageID else { return }

            guard let pendingIndex = self.rows.firstIndex(where: { $0.message.id == pendingAnchor.messageID }) else { return }
            let pendingRect = self.tableView.rect(ofRow: pendingIndex)
            let desiredY = pendingRect.origin.y + pendingAnchor.offsetInRow
            let currentY = self.scrollView.contentView.bounds.origin.y
            guard abs(currentY - desiredY) > 1.0 else { return }

            self.restoreScroll(anchor: pendingAnchor)
        }
    }

    private func triggerOlderMessagesLoadIfNeeded() {
        guard let container, container.hasMoreOlderMessages else { return }
        guard !container.isLoadingOlderMessages else { return }

        let now = Date.now
        guard now.timeIntervalSince(lastOlderLoadTriggerAt) >= olderLoadThrottleInterval else { return }
        lastOlderLoadTriggerAt = now

        Task { [container] in
            _ = await container.loadOlderMessagesIfNeeded()
        }
    }

    private func restoreScroll(anchor: ScrollAnchor) {
        guard let newIndex = rows.firstIndex(where: { $0.message.id == anchor.messageID }) else { return }
        guard newIndex >= 0, newIndex < tableView.numberOfRows else { return }

        _ = TailFollow.reduce(
            state: &tailFollowState,
            event: .programmaticScrollInitiated,
            config: tailFollowConfig,
            now: .now
        )

        let newRect = tableView.rect(ofRow: newIndex)
        setScrollOriginY(newRect.origin.y + anchor.offsetInRow)
        #if DEBUG
            scrollAnchorRestoreCountForTesting += 1
        #endif
    }

    private struct PrewarmCandidate {
        let messageID: UUID
        let input: MessageRenderInput
    }

    private func scheduleLookaheadPrewarm(visibleRows: NSRange) {
        #if DEBUG
            lookaheadScheduleInvocationCountForTesting += 1
        #endif
        guard let runtime else { return }
        let candidates = makeLookaheadPrewarmCandidates(
            visibleRows: visibleRows,
            availableWidth: effectiveAvailableWidth()
        )
        let candidateIDs = candidates.map(\.messageID)
        #if DEBUG
            lastLookaheadPrewarmIDsForTesting = candidateIDs
        #endif

        guard !candidates.isEmpty else {
            lookaheadPrewarmTask?.cancel()
            lookaheadPrewarmTask = nil
            lastLookaheadPrewarmIDs = []
            return
        }

        guard candidateIDs != lastLookaheadPrewarmIDs else { return }
        lastLookaheadPrewarmIDs = candidateIDs

        lookaheadPrewarmTask?.cancel()
        let inputs = candidates.map(\.input)
        lookaheadPrewarmTask = Task(priority: .utility) {
            await runtime.prewarm(inputs: inputs)
        }
    }

    private func makeLookaheadPrewarmCandidates(
        visibleRows: NSRange,
        availableWidth: CGFloat
    ) -> [PrewarmCandidate] {
        guard let runtime else { return [] }
        let indices = lookaheadIndices(visibleRows: visibleRows)
        guard !indices.isEmpty else { return [] }

        let style = renderStyle
        let contentWidth = max(1, availableWidth - HushSpacing.xl * 2)
        var candidates: [PrewarmCandidate] = []
        candidates.reserveCapacity(min(indices.count, lookaheadPrewarmMaxBatch))

        for index in indices {
            guard index >= 0, index < rows.count else { continue }
            let row = rows[index]
            guard row.message.role == .assistant else { continue }
            guard !row.isStreaming else { continue }

            let input = MessageRenderInput(
                content: row.message.content,
                availableWidth: contentWidth,
                style: style,
                isStreaming: false
            )
            guard runtime.peekCachedOutput(for: input) == nil else { continue }

            candidates.append(PrewarmCandidate(messageID: row.message.id, input: input))
            if candidates.count >= lookaheadPrewarmMaxBatch {
                break
            }
        }

        return candidates
    }

    private func lookaheadIndices(visibleRows: NSRange) -> [Int] {
        guard !rows.isEmpty else { return [] }
        guard visibleRows.length > 0 else { return [] }

        switch lastScrollDirection {
        case .up:
            let end = max(0, min(rows.count, visibleRows.location))
            guard end > 0 else { return [] }
            let start = max(0, end - lookaheadPrewarmWindow)
            guard start < end else { return [] }
            return Array(stride(from: end - 1, through: start, by: -1))
        case .down, .none:
            let start = max(0, visibleRows.location + visibleRows.length)
            let end = min(rows.count, start + lookaheadPrewarmWindow)
            guard start < end else { return [] }
            return Array(start ..< end)
        }
    }

    private func effectiveAvailableWidth() -> CGFloat {
        let raw = bounds.width > 1
            ? bounds.width
            : (HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2)
        return min(raw, HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2)
    }

    #if DEBUG
        func lookaheadCandidateMessageIDsForTesting(
            visibleRows: NSRange,
            availableWidth: CGFloat
        ) -> [UUID] {
            makeLookaheadPrewarmCandidates(
                visibleRows: visibleRows,
                availableWidth: availableWidth
            ).map(\.messageID)
        }
    #endif

    private func makeRankByMessageID(_ messages: [ChatMessage]) -> [UUID: Int] {
        let count = messages.count
        guard count > 0 else { return [:] }

        let requestedTailCount = max(16, RenderConstants.switchPriorityRenderCount)
        let tailCount = min(count, requestedTailCount)
        var ranks: [UUID: Int] = [:]
        ranks.reserveCapacity(tailCount)

        for offset in 0 ..< tailCount {
            let index = count - 1 - offset
            ranks[messages[index].id] = offset
        }
        return ranks
    }
}

final class MessageBodyTextView: NSTextView {
    var themePalette: HushThemePalette = HushColors.palette(for: .dark) {
        didSet {
            codeBlockCopyButtons.forEach { $0.themePalette = themePalette }
            needsDisplay = true
        }
    }

    private struct CodeBlockDescriptor {
        let containerRange: NSRange
        let contentRange: NSRange
        let hasHeader: Bool
    }

    private struct CodeBlockLayout {
        let backgroundFrame: NSRect
        let headerLineFrame: NSRect
        let copyButtonFrame: NSRect
        let contentRange: NSRange
        let hasHeader: Bool
    }

    private enum CodeBlockMetrics {
        static let cornerRadius: CGFloat = 12
        static let backgroundVerticalPadding: CGFloat = HushSpacing.sm
        static let backgroundHorizontalPadding: CGFloat = 0
        static let borderWidth: CGFloat = 1
        static let headerSeparatorInsetX: CGFloat = 12
        static let headerSeparatorOffsetY: CGFloat = 4

        static let copyButtonSize: CGFloat = 16
        static let copyButtonHitSize: CGFloat = 24
        static let copyButtonInsetX: CGFloat = 10
        static let copyButtonInsetY: CGFloat = 8
    }

    private final class CodeBlockCopyButton: NSButton {
        var themePalette: HushThemePalette = HushColors.palette(for: .dark) {
            didSet { updateVisualState() }
        }

        private weak var sourceTextView: NSTextView?
        private var contentRange: NSRange = .init(location: 0, length: 0)
        private var resetTask: Task<Void, Never>?
        private var isHovered = false
        private var isCopied = false
        private var trackingArea: NSTrackingArea?

        private static let copyImage: NSImage = .init(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copy"
        ) ?? NSImage()
        private static let copiedImage: NSImage = .init(
            systemSymbolName: "checkmark",
            accessibilityDescription: "Copied"
        ) ?? NSImage()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            isBordered = false
            bezelStyle = .shadowlessSquare
            image = Self.copyImage
            imagePosition = .imageOnly
            toolTip = "Copy code"
            target = self
            action = #selector(handleCopy)

            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.borderWidth = 1
            layer?.masksToBounds = true

            updateVisualState()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        deinit {
            resetTask?.cancel()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let options: NSTrackingArea.Options = [
                .activeInKeyWindow,
                .mouseEnteredAndExited,
                .inVisibleRect
            ]
            let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            isHovered = true
            updateVisualState()
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            isHovered = false
            updateVisualState()
        }

        func configure(sourceTextView: NSTextView, contentRange: NSRange) {
            self.sourceTextView = sourceTextView
            self.contentRange = contentRange
        }

        @objc private func handleCopy() {
            guard let sourceTextView, let storage = sourceTextView.textStorage else { return }
            guard contentRange.location != NSNotFound, NSMaxRange(contentRange) <= storage.length else { return }

            let code = storage.attributedSubstring(from: contentRange).string
            guard !code.isEmpty else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(code, forType: .string)

            resetTask?.cancel()
            isCopied = true
            updateVisualState()

            resetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let self, !Task.isCancelled else { return }
                self.isCopied = false
                self.updateVisualState()
            }
        }

        private func updateVisualState() {
            image = isCopied ? Self.copiedImage : Self.copyImage
            contentTintColor = isCopied
                ? NSColor(themePalette.successText)
                : (isHovered ? NSColor(themePalette.controlForeground) : NSColor(themePalette.controlForegroundMuted))
            layer?.backgroundColor = NSColor(isHovered ? themePalette.hoverFill : themePalette.softFillStrong).cgColor
            layer?.borderColor = NSColor(isHovered ? themePalette.hoverStroke : themePalette.subtleStroke).cgColor
        }
    }

    var cachedIntrinsicHeight: CGFloat? {
        didSet {
            if oldValue != cachedIntrinsicHeight {
                invalidateIntrinsicContentSize()
            }
        }
    }

    private var codeBlockDescriptors: [CodeBlockDescriptor] = []
    private var codeBlockLayouts: [CodeBlockLayout] = []
    private var codeBlockCopyButtons: [CodeBlockCopyButton] = []

    init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: textContainer)

        drawsBackground = false
        isEditable = false
        isSelectable = true
        isRichText = true
        importsGraphics = true
        // Our renderer already emits theme-aware colors directly.
        // Adaptive color mapping would remap those authored colors again,
        // causing inconsistent transcript output after theme switches.
        usesAdaptiveColorMappingForDarkAppearance = false
        allowsUndo = false

        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticDataDetectionEnabled = false

        textContainerInset = .zero
        textContainer.lineBreakMode = NSLineBreakMode.byWordWrapping
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        guard let textContainer else { return }
        guard bounds.width > 0 else { return }

        let targetWidth = max(1, bounds.width.rounded(.down))
        let nextSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
        if abs(textContainer.containerSize.width - nextSize.width) > 0.5 {
            textContainer.containerSize = nextSize
            cachedIntrinsicHeight = nil
        }

        updateCodeBlockLayouts()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCodeBlockBackgrounds(in: dirtyRect)
        super.draw(dirtyRect)
    }

    override var intrinsicContentSize: NSSize {
        if let cachedIntrinsicHeight {
            return NSSize(width: NSView.noIntrinsicMetric, height: max(1, cachedIntrinsicHeight))
        }
        return NSSize(width: NSView.noIntrinsicMetric, height: max(1, measuredHeight()))
    }

    func setAttributedText(_ text: NSAttributedString, cachedHeight: CGFloat?) {
        textStorage?.setAttributedString(text)
        cachedIntrinsicHeight = cachedHeight

        codeBlockDescriptors = scanCodeBlockDescriptors()
        reconcileCodeBlockCopyButtons()
        finalizeTextMutation()
    }

    func finalizeTextMutation() {
        if let layoutManager, let textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
        invalidateIntrinsicContentSize()
        updateCodeBlockLayouts()
        needsDisplay = true
    }

    func measuredHeight(safetyPadding: CGFloat = 4) -> CGFloat {
        guard let layoutManager, let textContainer else { return 1 }
        if bounds.width > 0 {
            let nextSize = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
            if textContainer.containerSize.width != nextSize.width {
                textContainer.containerSize = nextSize
            }
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        var nextPadding = safetyPadding
        if let textStorage,
           textStorage.length > 0,
           textStorage.attribute(.hushCodeBlockLanguage, at: textStorage.length - 1, effectiveRange: nil) != nil
        {
            nextPadding = max(nextPadding, CodeBlockMetrics.backgroundVerticalPadding + HushSpacing.xs)
        }
        return max(1, ceil(usedRect.height + nextPadding))
    }

    override func scrollWheel(with event: NSEvent) {
        let verticalMagnitude = abs(event.scrollingDeltaY)
        let horizontalMagnitude = abs(event.scrollingDeltaX)
        guard verticalMagnitude >= horizontalMagnitude else { return }
        nextResponder?.scrollWheel(with: event)
    }

    override func magnify(with _: NSEvent) {}

    override func rotate(with _: NSEvent) {}

    override func smartMagnify(with _: NSEvent) {}

    override func swipe(with _: NSEvent) {}

    private func scanCodeBlockDescriptors() -> [CodeBlockDescriptor] {
        guard let textStorage else { return [] }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return [] }

        var descriptors: [CodeBlockDescriptor] = []
        textStorage.enumerateAttribute(.hushCodeBlockLanguage, in: fullRange, options: []) { value, containerRange, _ in
            guard value != nil else { return }
            let contentRange = self.findCodeBlockContentRange(in: containerRange, textStorage: textStorage)
            let hasHeader = contentRange.location > containerRange.location
            descriptors.append(CodeBlockDescriptor(containerRange: containerRange, contentRange: contentRange, hasHeader: hasHeader))
        }
        return descriptors
    }

    private func findCodeBlockContentRange(
        in containerRange: NSRange,
        textStorage: NSTextStorage
    ) -> NSRange {
        var contentRange: NSRange?
        textStorage.enumerateAttribute(.hushCodeBlockContent, in: containerRange, options: []) { value, range, stop in
            guard value != nil else { return }
            contentRange = range
            stop.pointee = true
        }
        return contentRange ?? containerRange
    }

    private func reconcileCodeBlockCopyButtons() {
        while codeBlockCopyButtons.count > codeBlockDescriptors.count {
            let button = codeBlockCopyButtons.removeLast()
            button.removeFromSuperview()
        }
        while codeBlockCopyButtons.count < codeBlockDescriptors.count {
            let button = CodeBlockCopyButton(frame: .zero)
            button.themePalette = themePalette
            codeBlockCopyButtons.append(button)
            addSubview(button)
        }
    }

    // swiftlint:disable:next function_body_length
    private func updateCodeBlockLayouts() {
        guard let textStorage, let layoutManager, let textContainer else {
            codeBlockLayouts = []
            return
        }

        guard !codeBlockDescriptors.isEmpty else {
            if !codeBlockLayouts.isEmpty {
                codeBlockLayouts = []
                needsDisplay = true
            }
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let containerOrigin = textContainerOrigin
        let contentWidth = max(1, bounds.width - containerOrigin.x * 2)
        let buttonSize = CodeBlockMetrics.copyButtonSize
        var layouts: [CodeBlockLayout] = []
        layouts.reserveCapacity(codeBlockDescriptors.count)

        for descriptor in codeBlockDescriptors {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: descriptor.containerRange,
                actualCharacterRange: nil
            )
            guard glyphRange.location != NSNotFound else { continue }

            // Background frame: union of line fragments for the whole block.
            var unionRect = NSRect.null
            var firstUsedRect: NSRect?
            var lastUsedRect: NSRect?
            var glyphIndex = glyphRange.location
            while glyphIndex < NSMaxRange(glyphRange) {
                var effectiveRange = NSRange()
                let lineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: &effectiveRange
                )
                let usedRect = layoutManager.lineFragmentUsedRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: nil
                )
                unionRect = unionRect.union(lineRect)
                if firstUsedRect == nil {
                    firstUsedRect = usedRect
                }
                lastUsedRect = usedRect
                glyphIndex = NSMaxRange(effectiveRange)
            }

            if descriptor.containerRange.length > 0, unionRect != .null, textStorage.length > 0 {
                let startIndex = max(0, min(descriptor.containerRange.location, textStorage.length - 1))
                let endIndex = max(startIndex, min(NSMaxRange(descriptor.containerRange) - 1, textStorage.length - 1))

                let startParagraph = textStorage.attribute(.paragraphStyle, at: startIndex, effectiveRange: nil) as? NSParagraphStyle
                let endParagraph = textStorage.attribute(.paragraphStyle, at: endIndex, effectiveRange: nil) as? NSParagraphStyle

                let topTrim = max(0, startParagraph?.paragraphSpacingBefore ?? 0)
                let bottomTrim = max(0, endParagraph?.paragraphSpacing ?? 0)

                let trimmedMinY = unionRect.minY + min(topTrim, unionRect.height)
                let trimmedMaxY = unionRect.maxY - min(bottomTrim, unionRect.height)
                let minContentY = firstUsedRect?.minY ?? unionRect.minY
                let maxContentY = lastUsedRect?.maxY ?? unionRect.maxY
                let clampedMinY = min(trimmedMinY, minContentY)
                let clampedMaxY = max(trimmedMaxY, maxContentY)

                unionRect.origin.y = clampedMinY
                unionRect.size.height = max(0, clampedMaxY - clampedMinY)
            }

            let headerLineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil
            )

            var backgroundFrame = unionRect
            backgroundFrame.origin.x = 0
            backgroundFrame.size.width = contentWidth
            backgroundFrame = backgroundFrame.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
            backgroundFrame = backgroundFrame.insetBy(
                dx: -CodeBlockMetrics.backgroundHorizontalPadding,
                dy: -CodeBlockMetrics.backgroundVerticalPadding
            )

            let headerLineFrame = headerLineRect.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)

            let hitSize = CodeBlockMetrics.copyButtonHitSize
            let buttonX = backgroundFrame.maxX - CodeBlockMetrics.copyButtonInsetX - hitSize
            let buttonY =
                descriptor.hasHeader
                    ? (headerLineFrame.midY - hitSize / 2)
                    : (backgroundFrame.maxY - CodeBlockMetrics.copyButtonInsetY - hitSize)
            let copyButtonFrame = NSRect(
                x: max(backgroundFrame.minX, buttonX),
                y: max(backgroundFrame.minY, buttonY),
                width: hitSize,
                height: hitSize
            )

            layouts.append(CodeBlockLayout(
                backgroundFrame: backgroundFrame,
                headerLineFrame: headerLineFrame,
                copyButtonFrame: copyButtonFrame,
                contentRange: descriptor.contentRange,
                hasHeader: descriptor.hasHeader
            ))
        }

        codeBlockLayouts = layouts

        // Apply button frames + ranges.
        for (index, button) in codeBlockCopyButtons.enumerated() {
            guard index < codeBlockLayouts.count else {
                button.isHidden = true
                continue
            }
            let layout = codeBlockLayouts[index]
            button.isHidden = false
            button.configure(sourceTextView: self, contentRange: layout.contentRange)
            button.frame = layout.copyButtonFrame

            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.image?.size = NSSize(width: buttonSize, height: buttonSize)
        }

        needsDisplay = true
    }

    private func drawCodeBlockBackgrounds(in dirtyRect: NSRect) {
        guard !codeBlockLayouts.isEmpty else { return }

        let fillColor = NSColor(themePalette.codeBlockBackground)
        let borderColor = NSColor(themePalette.codeBlockBorder)
        let separatorColor = NSColor(themePalette.codeBlockSeparator)

        for layout in codeBlockLayouts where layout.backgroundFrame.intersects(dirtyRect) {
            let fillPath = NSBezierPath(
                roundedRect: layout.backgroundFrame,
                xRadius: CodeBlockMetrics.cornerRadius,
                yRadius: CodeBlockMetrics.cornerRadius
            )
            fillColor.setFill()
            fillPath.fill()

            let strokeInset = CodeBlockMetrics.borderWidth / 2
            let strokeRect = layout.backgroundFrame.insetBy(dx: strokeInset, dy: strokeInset)
            let strokeRadius = max(0, CodeBlockMetrics.cornerRadius - strokeInset)
            let strokePath = NSBezierPath(
                roundedRect: strokeRect,
                xRadius: strokeRadius,
                yRadius: strokeRadius
            )
            borderColor.setStroke()
            strokePath.lineWidth = CodeBlockMetrics.borderWidth
            strokePath.stroke()

            // Header separator (between language header and code).
            if layout.hasHeader {
                let separatorY = layout.headerLineFrame.maxY + CodeBlockMetrics.headerSeparatorOffsetY
                let start = NSPoint(
                    x: layout.backgroundFrame.minX + CodeBlockMetrics.headerSeparatorInsetX,
                    y: separatorY
                )
                let end = NSPoint(
                    x: layout.backgroundFrame.maxX - CodeBlockMetrics.headerSeparatorInsetX,
                    y: separatorY
                )
                let separatorPath = NSBezierPath()
                separatorPath.move(to: start)
                separatorPath.line(to: end)
                separatorColor.setStroke()
                separatorPath.lineCapStyle = .round
                separatorPath.lineWidth = 1
                separatorPath.stroke()
            }
        }
    }
}

@MainActor
final class MessageTableCellView: NSTableCellView {
    private struct RenderInputFingerprint: Equatable {
        let messageID: UUID
        let contentHash: Int
        let attachmentHash: Int
        let debugInfoHash: Int
        let generation: UInt64
        let isStreaming: Bool
        let contentWidth: Int
        let styleKey: Int
    }

    private let contentContainer = NSView()
    private let metaLabel = NSTextField(labelWithString: "")
    private let bodyTextView = MessageBodyTextView()
    private let attachmentPreviewView = MessageAttachmentPreviewView()
    private let debugButton = MessageActionOverlayButton(
        frame: .zero,
        defaultSymbolName: "point.3.connected.trianglepath.dotted",
        copiedSymbolName: "point.3.connected.trianglepath.dotted",
        defaultToolTip: "View request trace",
        copiedToolTip: "View request trace"
    )
    private let copyButton = MessageActionOverlayButton(
        frame: .zero,
        defaultSymbolName: "doc.on.doc",
        defaultToolTip: "Copy message",
        copiedToolTip: "Copied"
    )
    private weak var owningTableView: NSTableView?
    private weak var messageTableView: MessageTableView?
    private var hoverTrackingArea: NSTrackingArea?
    private var isMouseHovering = false
    private var bodyBottomWithoutActionBar: NSLayoutConstraint!
    private var copyButtonTopToBodyConstraint: NSLayoutConstraint!
    private var copyButtonTopToPreviewConstraint: NSLayoutConstraint!
    private var copyButtonBottomConstraint: NSLayoutConstraint!
    private var copyButtonHeightConstraint: NSLayoutConstraint!
    private var copyButtonLeadingToBodyConstraint: NSLayoutConstraint!
    private var copyButtonLeadingToDebugConstraint: NSLayoutConstraint!
    private var copyButtonWidthConstraint: NSLayoutConstraint!
    private var debugButtonTopToBodyConstraint: NSLayoutConstraint!
    private var debugButtonTopToPreviewConstraint: NSLayoutConstraint!
    private var debugButtonBottomConstraint: NSLayoutConstraint!
    private var debugButtonHeightConstraint: NSLayoutConstraint!
    private var debugButtonLeadingConstraint: NSLayoutConstraint!
    private var debugButtonWidthConstraint: NSLayoutConstraint!
    private var previewTopConstraint: NSLayoutConstraint!
    private var previewLeadingConstraint: NSLayoutConstraint!
    private var previewTrailingConstraint: NSLayoutConstraint!
    private var previewBottomConstraint: NSLayoutConstraint!
    private var isActionBarActive = false
    private var isPreviewVisible = false
    private var isDebugButtonVisible = false
    private var renderController: RenderController?
    private var outputObservation: AnyCancellable?
    private weak var container: AppContainer?
    private var renderRuntime: MessageRenderRuntime?
    private var currentRow: MessageTableView.RowModel?
    private var currentRowIndex: Int?
    private var lastFingerprint: RenderInputFingerprint?
    private var streamingDisplayedLength: Int = 0
    private var currentContentWidth: CGFloat = 0
    private var isShowingStreamingRichOutput = false
    private var theme: AppTheme = .dark {
        didSet {
            metaLabel.textColor = NSColor(palette.secondaryText)
            bodyTextView.themePalette = palette
            debugButton.themePalette = palette
            copyButton.themePalette = palette
        }
    }

    private var fontSettings: AppFontSettings = .default {
        didSet {
            metaLabel.font = HushFontResolver.contentFont(
                settings: fontSettings,
                referenceSize: 11,
                weight: .semibold
            )
        }
    }

    private var palette: HushThemePalette {
        HushColors.palette(for: theme)
    }

    private var renderStyle: RenderStyle {
        RenderStyle.fromPalette(palette, fontSettings: fontSettings)
    }

    private var plainTextAttributes: [NSAttributedString.Key: Any] {
        return [
            .font: HushFontResolver.contentFont(settings: fontSettings, referenceSize: 14),
            .foregroundColor: NSColor(palette.primaryText)
        ]
    }

    #if DEBUG
        // swiftlint:disable identifier_name
        private(set) var renderRequestCountForTesting = 0
        private(set) var streamingUpdateAssignmentsForTesting = 0
        private(set) var richOutputHeightInvalidationCountForTesting = 0
        // swiftlint:enable identifier_name
    #endif

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        translatesAutoresizingMaskIntoConstraints = false

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        let maxContentWidth = HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2
        let fillLeading = contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor)
        fillLeading.priority = .defaultLow
        let fillTrailing = contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor)
        fillTrailing.priority = .defaultLow
        let preferredWidth = contentContainer.widthAnchor.constraint(equalToConstant: maxContentWidth)
        preferredWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentContainer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            contentContainer.widthAnchor.constraint(lessThanOrEqualToConstant: maxContentWidth),
            fillLeading,
            fillTrailing,
            preferredWidth
        ])

        metaLabel.font = HushFontResolver.contentFont(
            settings: fontSettings,
            referenceSize: 11,
            weight: .semibold
        )
        metaLabel.textColor = NSColor(palette.secondaryText)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyTextView.translatesAutoresizingMaskIntoConstraints = false
        bodyTextView.setContentCompressionResistancePriority(.required, for: .vertical)
        bodyTextView.setContentHuggingPriority(.required, for: .vertical)

        contentContainer.addSubview(metaLabel)
        contentContainer.addSubview(bodyTextView)
        attachmentPreviewView.translatesAutoresizingMaskIntoConstraints = false
        attachmentPreviewView.isHidden = true
        contentContainer.addSubview(attachmentPreviewView)

        debugButton.translatesAutoresizingMaskIntoConstraints = false
        debugButton.alphaValue = 0
        debugButton.isHidden = true
        debugButton.target = self
        debugButton.action = #selector(handleDebugButtonPressed)
        contentContainer.addSubview(debugButton)

        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.alphaValue = 0
        copyButton.isHidden = true
        copyButton.target = self
        copyButton.action = #selector(handleCopyButtonPressed)
        contentContainer.addSubview(copyButton)

        bodyBottomWithoutActionBar = bodyTextView.bottomAnchor.constraint(
            equalTo: contentContainer.bottomAnchor,
            constant: -HushSpacing.sm
        )
        previewTopConstraint = attachmentPreviewView.topAnchor.constraint(equalTo: bodyTextView.bottomAnchor, constant: HushSpacing.sm)
        previewLeadingConstraint = attachmentPreviewView.leadingAnchor.constraint(equalTo: bodyTextView.leadingAnchor)
        previewTrailingConstraint = attachmentPreviewView.trailingAnchor.constraint(equalTo: bodyTextView.trailingAnchor)
        previewBottomConstraint = attachmentPreviewView.bottomAnchor.constraint(
            equalTo: contentContainer.bottomAnchor,
            constant: -HushSpacing.sm
        )
        debugButtonTopToBodyConstraint = debugButton.topAnchor.constraint(equalTo: bodyTextView.bottomAnchor, constant: HushSpacing.sm)
        debugButtonTopToPreviewConstraint = debugButton.topAnchor.constraint(
            equalTo: attachmentPreviewView.bottomAnchor,
            constant: HushSpacing.sm
        )
        debugButtonBottomConstraint = debugButton.bottomAnchor.constraint(
            equalTo: contentContainer.bottomAnchor,
            constant: -HushSpacing.sm
        )
        debugButtonHeightConstraint = debugButton.heightAnchor.constraint(equalToConstant: HushSpacing.xl)
        debugButtonLeadingConstraint = debugButton.leadingAnchor.constraint(equalTo: bodyTextView.leadingAnchor)
        debugButtonWidthConstraint = debugButton.widthAnchor.constraint(equalToConstant: HushSpacing.xl)
        copyButtonTopToBodyConstraint = copyButton.topAnchor.constraint(equalTo: bodyTextView.bottomAnchor, constant: HushSpacing.sm)
        copyButtonTopToPreviewConstraint = copyButton.topAnchor.constraint(
            equalTo: attachmentPreviewView.bottomAnchor,
            constant: HushSpacing.sm
        )
        copyButtonBottomConstraint = copyButton.bottomAnchor.constraint(
            equalTo: contentContainer.bottomAnchor,
            constant: -HushSpacing.sm
        )
        copyButtonHeightConstraint = copyButton.heightAnchor.constraint(equalToConstant: HushSpacing.xl)
        copyButtonLeadingToBodyConstraint = copyButton.leadingAnchor.constraint(equalTo: bodyTextView.leadingAnchor)
        copyButtonLeadingToDebugConstraint = copyButton.leadingAnchor.constraint(equalTo: debugButton.trailingAnchor, constant: HushSpacing.xs)
        copyButtonWidthConstraint = copyButton.widthAnchor.constraint(equalToConstant: HushSpacing.xl)

        NSLayoutConstraint.activate([
            metaLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: HushSpacing.xl),
            metaLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -HushSpacing.xl),
            metaLabel.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: HushSpacing.sm),
            bodyTextView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: HushSpacing.xl),
            bodyTextView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -HushSpacing.xl),
            bodyTextView.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: HushSpacing.xs),
            bodyBottomWithoutActionBar
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.size.width
        let previousHeight = bodyIntrinsicHeight
        super.setFrameSize(newSize)
        if abs(oldWidth - newSize.width) > 0.5 {
            needsUpdateConstraints = true
            contentContainer.needsUpdateConstraints = true
            contentContainer.needsLayout = true
            needsLayout = true
            refreshAttachmentPreviewForCurrentWidth(previousHeight: previousHeight)
        }
    }

    override func layout() {
        let previousHeight = bodyIntrinsicHeight
        super.layout()
        refreshAttachmentPreviewForCurrentWidth(previousHeight: previousHeight)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelRenderWork()
        currentRow = nil
        currentRowIndex = nil
        streamingDisplayedLength = 0
        currentContentWidth = 0
        renderRuntime = nil
        isShowingStreamingRichOutput = false
        owningTableView = nil
        messageTableView = nil
        isMouseHovering = false
        NSLayoutConstraint.deactivate([
            previewTopConstraint,
            previewLeadingConstraint,
            previewTrailingConstraint,
            previewBottomConstraint,
            debugButtonTopToBodyConstraint,
            debugButtonTopToPreviewConstraint,
            debugButtonBottomConstraint,
            debugButtonHeightConstraint,
            debugButtonLeadingConstraint,
            debugButtonWidthConstraint,
            copyButtonTopToBodyConstraint,
            copyButtonTopToPreviewConstraint,
            copyButtonBottomConstraint,
            copyButtonHeightConstraint,
            copyButtonLeadingToBodyConstraint,
            copyButtonLeadingToDebugConstraint,
            copyButtonWidthConstraint
        ])
        bodyBottomWithoutActionBar.isActive = true
        isActionBarActive = false
        isDebugButtonVisible = false
        debugButton.resetState()
        debugButton.alphaValue = 0
        debugButton.isHidden = true
        copyButton.resetState()
        copyButton.alphaValue = 0
        copyButton.isHidden = true
        bodyTextView.setAttributedText(NSAttributedString(), cachedHeight: nil)
        attachmentPreviewView.reset()
        isPreviewVisible = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isMouseHovering = true
        if isActionBarActive { setActionButtonsVisible(true, animated: true) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isMouseHovering = false
        if isActionBarActive { setActionButtonsVisible(false, animated: true) }
    }

    func cancelRenderWork() {
        cancelRenderWork(resetFingerprint: true)
    }

    private func cancelRenderWork(resetFingerprint: Bool) {
        outputObservation?.cancel()
        outputObservation = nil
        if let renderController {
            renderController.cancel()
            self.renderController = nil
        }
        isShowingStreamingRichOutput = false
        if resetFingerprint {
            lastFingerprint = nil
        }
    }

    var bodyIntrinsicHeight: CGFloat {
        bodyTextView.intrinsicContentSize.height + attachmentPreviewView.renderedHeight
    }

    func updateStreamingText(_ content: String) {
        updateCurrentRowContent(content)

        let shouldRenderStreamingRich = shouldUseStreamingRichRender(for: content)
        if !isShowingStreamingRichOutput {
            applyStreamingPlainText(content)
        }

        guard shouldRenderStreamingRich else { return }
        if let runtime = renderRuntime, let currentRow {
            ensureRenderController(
                runtime: runtime,
                observedRow: currentRow,
                contentWidth: currentContentWidth,
                owningTableView: owningTableView,
                rowIndex: currentRowIndex,
                messageTableView: messageTableView
            )
        }
        requestStreamingRichRender(content: content)
    }

    private func updateCurrentRowContent(_ content: String) {
        guard let currentRow else { return }
        guard currentRow.message.content != content else { return }

        let updatedMessage = currentRow.message.updatingContent(content)
        self.currentRow = MessageTableView.RowModel(
            message: updatedMessage,
            isStreaming: currentRow.isStreaming,
            renderHint: currentRow.renderHint
        )
    }

    private static func shouldShowStreamingWaitingState(for content: String) -> Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func streamingFallbackText(for content: String) -> String {
        Self.shouldShowStreamingWaitingState(for: content)
            ? RenderConstants.assistantWaitingPlaceholder
            : content
    }

    private func isStreamingWaitingOutput(
        _ output: MessageRenderOutput,
        for row: MessageTableView.RowModel
    ) -> Bool {
        row.isStreaming
            && Self.shouldShowStreamingWaitingState(for: row.message.content)
            && output.plainText == RenderConstants.assistantWaitingPlaceholder
    }

    private static func containsClosedMathSegment(_ content: String) -> Bool {
        guard content.contains("$") else { return false }
        return MathSegmenter.segment(content).contains { segment in
            switch segment {
            case .inlineMath, .blockMath:
                return true
            case .text:
                return false
            }
        }
    }

    private static func containsStableMarkdownCue(_ content: String) -> Bool {
        if containsPairedDelimiter("**", in: content)
            || containsPairedDelimiter("__", in: content)
            || containsPairedDelimiter("~~", in: content)
            || containsPairedDelimiter("`", in: content)
        {
            return true
        }

        if content.contains("["),
           content.contains("](")
        {
            return true
        }

        return content
            .components(separatedBy: .newlines)
            .contains(where: containsRenderableMarkdownLine)
    }

    private static func containsPairedDelimiter(_ delimiter: String, in content: String) -> Bool {
        var searchRange = content.startIndex ..< content.endIndex
        var matchCount = 0

        while let range = content.range(of: delimiter, range: searchRange) {
            matchCount += 1
            if matchCount >= 2 {
                return true
            }
            searchRange = range.upperBound ..< content.endIndex
        }

        return false
    }

    private static func containsRenderableMarkdownLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("```")
            || trimmed.hasPrefix("~~~")
            || trimmed.hasPrefix("> ")
            || trimmed.hasPrefix("- ")
            || trimmed.hasPrefix("* ")
            || trimmed.hasPrefix("+ ")
        {
            return true
        }

        if isMarkdownHeadingLine(trimmed) || isOrderedListLine(trimmed) {
            return true
        }

        return false
    }

    private static func isMarkdownHeadingLine(_ line: String) -> Bool {
        let headingMarks = line.prefix { $0 == "#" }
        guard !headingMarks.isEmpty, headingMarks.count <= 6 else { return false }
        guard headingMarks.endIndex < line.endIndex else { return false }
        return line[headingMarks.endIndex] == " "
    }

    private static func isOrderedListLine(_ line: String) -> Bool {
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            index = line.index(after: index)
        }

        guard index > line.startIndex, index < line.endIndex, line[index] == "." else {
            return false
        }

        let separatorIndex = line.index(after: index)
        guard separatorIndex < line.endIndex else { return false }
        return line[separatorIndex] == " "
    }

    private func shouldUseStreamingRichRender(for content: String) -> Bool {
        Self.shouldShowStreamingWaitingState(for: content)
            || isShowingStreamingRichOutput
            || Self.containsClosedMathSegment(content)
            || Self.containsStableMarkdownCue(content)
    }

    // swiftlint:disable:next function_parameter_count
    private func ensureRenderController(
        runtime: MessageRenderRuntime,
        observedRow: MessageTableView.RowModel,
        contentWidth: CGFloat,
        owningTableView: NSTableView?,
        rowIndex: Int?,
        messageTableView: MessageTableView?
    ) {
        if renderController == nil {
            renderController = runtime.makeRenderController()
        }

        guard let renderController else { return }
        outputObservation?.cancel()
        outputObservation = renderController.$currentOutput.sink { [weak self, weak messageTableView] output in
            guard let self, let output else { return }
            guard let activeRow = self.validatedRowForOutput(output, observedRow: observedRow) else { return }

            let previousHeight = self.bodyIntrinsicHeight
            let cachedHeight: CGFloat?
            if activeRow.isStreaming {
                let isWaitingOutput = self.isStreamingWaitingOutput(output, for: activeRow)
                cachedHeight = nil
                self.streamingDisplayedLength = isWaitingOutput
                    ? activeRow.message.content.count
                    : max(self.streamingDisplayedLength, output.plainText.count)
                self.isShowingStreamingRichOutput = !isWaitingOutput
            } else {
                let heightInput = MessageRenderInput(
                    content: activeRow.message.content,
                    availableWidth: contentWidth,
                    style: renderStyle,
                    isStreaming: false
                )
                cachedHeight = runtime.cachedRowHeight(for: heightInput)
                self.streamingDisplayedLength = 0
                self.isShowingStreamingRichOutput = false
            }

            self.bodyTextView.setAttributedText(
                output.attributedString,
                cachedHeight: cachedHeight
            )
            self.invalidateOwningRowHeightIfNeeded(
                owningTableView: owningTableView,
                rowIndex: rowIndex,
                previousHeight: previousHeight,
                messageTableView: messageTableView
            )

            if !activeRow.isStreaming {
                self.container?.reportActiveConversationRichRenderReadyIfNeeded()
            }
        }
    }

    private func requestStreamingRichRender(content: String) {
        guard let runtime = renderRuntime else { return }
        guard currentContentWidth > 0 else { return }
        guard let currentRow else { return }

        if renderController == nil {
            renderController = runtime.makeRenderController()
        }
        guard let renderController else { return }

        #if DEBUG
            renderRequestCountForTesting += 1
        #endif
        renderController.requestRender(
            content: content,
            availableWidth: currentContentWidth,
            style: renderStyle,
            isStreaming: true,
            hint: currentRow.renderHint
        )
    }

    private func applyStreamingPlainText(_ content: String) {
        let fallbackText = streamingFallbackText(for: content)
        let existing = bodyTextView.textStorage?.string ?? ""
        if existing == fallbackText {
            streamingDisplayedLength = max(streamingDisplayedLength, content.count)
            return
        }

        if fallbackText == content,
           !existing.isEmpty,
           content.hasPrefix(existing),
           let textStorage = bodyTextView.textStorage
        {
            let delta = String(content.dropFirst(existing.count))
            if !delta.isEmpty {
                textStorage.beginEditing()
                textStorage.append(NSAttributedString(string: delta, attributes: plainTextAttributes))
                textStorage.endEditing()
                bodyTextView.cachedIntrinsicHeight = nil
                bodyTextView.finalizeTextMutation()
                #if DEBUG
                    streamingUpdateAssignmentsForTesting += 1
                #endif
            }
        } else {
            bodyTextView.setAttributedText(
                NSAttributedString(string: fallbackText, attributes: plainTextAttributes),
                cachedHeight: nil
            )
            #if DEBUG
                streamingUpdateAssignmentsForTesting += 1
            #endif
        }

        streamingDisplayedLength = content.count
    }

    private func applyPlainText(_ content: String, cachedHeight: CGFloat?) {
        bodyTextView.setAttributedText(
            NSAttributedString(string: content, attributes: plainTextAttributes),
            cachedHeight: cachedHeight
        )
    }

    private static func expectedRenderedPlainText(for content: String) -> String {
        if content.count > RenderConstants.maxRichRenderLength {
            return String(content.prefix(RenderConstants.maxRichRenderLength))
        }
        return content
    }

    private func validatedRowForOutput(
        _ output: MessageRenderOutput,
        observedRow: MessageTableView.RowModel
    ) -> MessageTableView.RowModel? {
        guard let activeRow = currentRow else { return nil }
        guard activeRow.message.id == observedRow.message.id else { return nil }

        if activeRow.isStreaming {
            let minimumLength = min(
                streamingDisplayedLength,
                RenderConstants.maxRichRenderLength
            )
            guard output.plainText.count >= minimumLength else { return nil }
            return activeRow
        }

        let expectedPlainText = Self.expectedRenderedPlainText(for: activeRow.message.content)
        guard output.plainText == expectedPlainText else { return nil }
        return activeRow
    }

    private func invalidateOwningRowHeightIfNeeded(
        owningTableView: NSTableView?,
        rowIndex: Int?,
        previousHeight: CGFloat,
        messageTableView: MessageTableView? = nil
    ) {
        guard let owningTableView, let rowIndex else { return }
        guard rowIndex >= 0, rowIndex < owningTableView.numberOfRows else { return }
        guard owningTableView.numberOfColumns > 0 else { return }
        guard let viewAtRow = owningTableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: false),
              viewAtRow === self
        else { return }

        let nextHeight = bodyIntrinsicHeight
        guard abs(nextHeight - previousHeight) > .ulpOfOne else { return }

        if let messageTableView, messageTableView.shouldDeferPinnedRowHeightInvalidation {
            messageTableView.enqueuePinnedRowHeightInvalidation(rowIndex: rowIndex)
            return
        }

        if let messageTableView {
            messageTableView.requestRowHeightInvalidation(rowIndex: rowIndex)
        } else {
            owningTableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: rowIndex))
        }
        #if DEBUG
            richOutputHeightInvalidationCountForTesting += 1
        #endif
    }

    // swiftlint:disable:next function_body_length
    func configure(
        row: MessageTableView.RowModel,
        runtime: MessageRenderRuntime,
        availableWidth: CGFloat,
        theme: AppTheme = .dark,
        container: AppContainer?,
        owningTableView: NSTableView? = nil,
        rowIndex: Int? = nil,
        messageTableView: MessageTableView? = nil
    ) {
        self.owningTableView = owningTableView
        self.messageTableView = messageTableView
        currentRowIndex = rowIndex
        renderRuntime = runtime
        self.theme = theme
        fontSettings = container?.settings.fontSettings ?? .default

        let contentWidth = max(1, availableWidth - HushSpacing.xl * 2)
        currentContentWidth = contentWidth
        let fingerprint = RenderInputFingerprint(
            messageID: row.message.id,
            contentHash: row.message.content.hashValue,
            attachmentHash: Self.attachmentHash(row.message.attachments),
            debugInfoHash: row.message.debugInfoJSON?.hashValue ?? 0,
            generation: row.renderHint.switchGeneration,
            isStreaming: row.isStreaming,
            contentWidth: Int(contentWidth.rounded(.down)),
            styleKey: renderStyle.cacheKey
        )
        if fingerprint == lastFingerprint {
            return
        }
        lastFingerprint = fingerprint

        let previousRow = currentRow
        self.container = container
        currentRow = row

        metaLabel.stringValue = roleDisplayName(row.message.role) + "  " + Self.timeString(from: row.message.createdAt)
        outputObservation?.cancel()
        outputObservation = nil
        bodyTextView.cachedIntrinsicHeight = nil

        let supportsTraceButton = row.message.role == .assistant || row.message.role == .user
        let shouldShowDebugButton = supportsTraceButton
            && !row.isStreaming
            && row.message.debugInfoJSON != nil
        let shouldShowCopyButton = row.message.role == .assistant && !row.isStreaming
        let shouldShowActionBar = shouldShowDebugButton || shouldShowCopyButton
        let renderableAttachment = row.message.attachments.first(where: { $0.kind == .image })
        updateAttachmentPreview(attachment: renderableAttachment, availableWidth: contentWidth)
        updateActionBarLayout(
            showActionBar: shouldShowActionBar,
            showPreview: renderableAttachment != nil,
            showDebugButton: shouldShowDebugButton,
            showCopyButton: shouldShowCopyButton
        )

        guard row.message.role == ChatRole.assistant else {
            applyPlainText(row.message.content, cachedHeight: nil)
            streamingDisplayedLength = 0
            cancelRenderWork(resetFingerprint: false)
            return
        }

        if row.isStreaming {
            let shouldRenderStreamingRich = shouldUseStreamingRichRender(for: row.message.content)
            let shouldSkipStreamingFallback =
                previousRow?.isStreaming == true
                    && row.message.content.count < streamingDisplayedLength
            if !shouldSkipStreamingFallback, !isShowingStreamingRichOutput {
                applyPlainText(streamingFallbackText(for: row.message.content), cachedHeight: nil)
                streamingDisplayedLength = row.message.content.count
            }

            guard shouldRenderStreamingRich else {
                cancelRenderWork(resetFingerprint: false)
                return
            }

            ensureRenderController(
                runtime: runtime,
                observedRow: row,
                contentWidth: contentWidth,
                owningTableView: owningTableView,
                rowIndex: rowIndex,
                messageTableView: messageTableView
            )
            if !shouldSkipStreamingFallback || isShowingStreamingRichOutput {
                requestStreamingRichRender(content: row.message.content)
            }
            return
        }

        isShowingStreamingRichOutput = false

        if !row.isStreaming {
            let input = MessageRenderInput(
                content: row.message.content,
                availableWidth: contentWidth,
                style: renderStyle,
                isStreaming: false
            )
            if let cached = runtime.cachedOutput(for: input) {
                let previousHeight = bodyIntrinsicHeight
                bodyTextView.setAttributedText(
                    cached.attributedString,
                    cachedHeight: runtime.cachedRowHeight(for: input)
                )
                invalidateOwningRowHeightIfNeeded(
                    owningTableView: owningTableView,
                    rowIndex: rowIndex,
                    previousHeight: previousHeight,
                    messageTableView: messageTableView
                )
                streamingDisplayedLength = 0
                container?.reportActiveConversationRichRenderReadyIfNeeded()
                cancelRenderWork(resetFingerprint: false)
                return
            }
        }

        // Cache miss: show plain fallback, then async rich render.
        applyPlainText(row.message.content, cachedHeight: nil)
        streamingDisplayedLength = 0

        if renderController == nil {
            renderController = runtime.makeRenderController()
        }

        ensureRenderController(
            runtime: runtime,
            observedRow: row,
            contentWidth: contentWidth,
            owningTableView: owningTableView,
            rowIndex: rowIndex,
            messageTableView: messageTableView
        )

        #if DEBUG
            renderRequestCountForTesting += 1
        #endif
        guard let renderController else { return }
        renderController.requestRender(
            content: row.message.content,
            availableWidth: contentWidth,
            style: renderStyle,
            isStreaming: false,
            hint: row.renderHint
        )
    }

    private func updateAttachmentPreview(attachment: MessageAttachment?, availableWidth: CGFloat) {
        guard let attachment else {
            attachmentPreviewView.reset()
            return
        }
        attachmentPreviewView.configure(
            attachment: attachment,
            resolvedURL: container?.resolveURL(for: attachment),
            availableWidth: availableWidth,
            palette: palette
        )
    }

    private func refreshAttachmentPreviewForCurrentWidth(previousHeight: CGFloat) {
        guard let row = currentRow,
              row.message.attachments.contains(where: { $0.kind == .image }),
              !attachmentPreviewView.isHidden
        else {
            return
        }

        let maxAvailableWidth = HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2
        let clampedAvailableWidth = min(bounds.width, maxAvailableWidth)
        let nextContentWidth = max(1, (clampedAvailableWidth - HushSpacing.xl * 2).rounded(.down))
        guard abs(nextContentWidth - currentContentWidth) > 0.5 else { return }

        currentContentWidth = nextContentWidth
        if attachmentPreviewView.updateAvailableWidth(nextContentWidth) {
            invalidateOwningRowHeightIfNeeded(
                owningTableView: owningTableView,
                rowIndex: currentRowIndex,
                previousHeight: previousHeight,
                messageTableView: messageTableView
            )
        }
    }

    private func updateActionBarLayout(
        showActionBar: Bool,
        showPreview: Bool,
        showDebugButton: Bool,
        showCopyButton: Bool
    ) {
        guard showActionBar != isActionBarActive
            || showPreview != isPreviewVisible
            || showDebugButton != isDebugButtonVisible
            || showCopyButton != !copyButton.isHidden
        else {
            return
        }
        isActionBarActive = showActionBar
        isPreviewVisible = showPreview
        isDebugButtonVisible = showDebugButton

        NSLayoutConstraint.deactivate([
            bodyBottomWithoutActionBar,
            previewTopConstraint,
            previewLeadingConstraint,
            previewTrailingConstraint,
            previewBottomConstraint,
            debugButtonTopToBodyConstraint,
            debugButtonTopToPreviewConstraint,
            debugButtonBottomConstraint,
            debugButtonHeightConstraint,
            debugButtonLeadingConstraint,
            debugButtonWidthConstraint,
            copyButtonTopToBodyConstraint,
            copyButtonTopToPreviewConstraint,
            copyButtonBottomConstraint,
            copyButtonHeightConstraint,
            copyButtonLeadingToBodyConstraint,
            copyButtonLeadingToDebugConstraint,
            copyButtonWidthConstraint
        ])

        if showPreview {
            NSLayoutConstraint.activate([
                previewTopConstraint,
                previewLeadingConstraint,
                previewTrailingConstraint
            ])
        }

        if showActionBar {
            let debugTopConstraint: NSLayoutConstraint = showPreview ? debugButtonTopToPreviewConstraint : debugButtonTopToBodyConstraint
            let copyTopConstraint: NSLayoutConstraint = showPreview ? copyButtonTopToPreviewConstraint : copyButtonTopToBodyConstraint
            if showDebugButton {
                NSLayoutConstraint.activate([
                    debugTopConstraint,
                    debugButtonBottomConstraint,
                    debugButtonHeightConstraint,
                    debugButtonLeadingConstraint,
                    debugButtonWidthConstraint
                ])
                NSLayoutConstraint.activate([
                    copyTopConstraint,
                    copyButtonBottomConstraint,
                    copyButtonHeightConstraint,
                    copyButtonLeadingToDebugConstraint,
                    copyButtonWidthConstraint
                ])
            } else if showCopyButton {
                NSLayoutConstraint.activate([
                    copyTopConstraint,
                    copyButtonBottomConstraint,
                    copyButtonHeightConstraint,
                    copyButtonLeadingToBodyConstraint,
                    copyButtonWidthConstraint
                ])
            }
            debugButton.isHidden = !showDebugButton
            debugButton.alphaValue = showDebugButton && isMouseHovering ? 1 : 0
            copyButton.isHidden = !showCopyButton
            copyButton.alphaValue = showCopyButton && isMouseHovering ? 1 : 0
        } else {
            if showPreview {
                previewBottomConstraint.isActive = true
            } else {
                bodyBottomWithoutActionBar.isActive = true
            }
            debugButton.isHidden = true
            debugButton.alphaValue = 0
            copyButton.isHidden = true
            copyButton.alphaValue = 0
        }
    }

    private func setActionButtonsVisible(_ isVisible: Bool, animated: Bool) {
        let targetAlpha: CGFloat = isVisible ? 1 : 0

        let updateAlpha = { [self] in
            if isDebugButtonVisible {
                debugButton.alphaValue = targetAlpha
            }
            if !copyButton.isHidden {
                copyButton.alphaValue = targetAlpha
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                if isDebugButtonVisible {
                    debugButton.animator().alphaValue = targetAlpha
                }
                if !copyButton.isHidden {
                    copyButton.animator().alphaValue = targetAlpha
                }
            }
        } else {
            updateAlpha()
        }
    }

    @objc private func handleDebugButtonPressed() {
        guard let row = currentRow,
              let debugInfoJSON = row.message.debugInfoJSON,
              !debugInfoJSON.isEmpty
        else {
            return
        }

        MessageTraceSheetPresenter.present(
            message: row.message,
            rawDebugInfoJSON: debugInfoJSON,
            theme: theme,
            from: window
        )
    }

    @objc private func handleCopyButtonPressed() {
        guard let row = currentRow else { return }
        guard row.message.role == .assistant else { return }
        guard !row.isStreaming else { return }

        let content = row.message.content
        guard !content.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        copyButton.flashCopied()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func timeString(from date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private func roleDisplayName(_ role: ChatRole) -> String {
        switch role {
        case .assistant:
            return "Assistant"
        case .tool:
            return "Tool"
        case .system:
            return "System"
        case .user:
            return "You"
        }
    }

    private static func attachmentHash(_ attachments: [MessageAttachment]) -> Int {
        attachments
            .map {
                [
                    $0.id.uuidString,
                    $0.kind.rawValue,
                    $0.localRelativePath,
                    $0.mimeType,
                    $0.pixelWidth.map(String.init) ?? "",
                    $0.pixelHeight.map(String.init) ?? "",
                    $0.sha256,
                    $0.sourcePrompt,
                    $0.providerMetadataJSON ?? ""
                ].joined(separator: "|")
            }
            .joined(separator: "::")
            .hashValue
    }
}

@MainActor
private final class MessageAttachmentPreviewView: NSView {
    private let imageView = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "Image unavailable")
    private var heightConstraint: NSLayoutConstraint!
    private var currentAttachment: MessageAttachment?
    private var currentResolvedURL: URL?
    private var currentIntrinsicSize = NSSize(width: 1, height: 1)

    var renderedHeight: CGFloat {
        isHidden ? 0 : heightConstraint.constant + HushSpacing.sm
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.alignment = .center
        placeholderLabel.isHidden = true

        addSubview(imageView)
        addSubview(placeholderLabel)

        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func configure(
        attachment: MessageAttachment,
        resolvedURL: URL?,
        availableWidth: CGFloat,
        palette: HushThemePalette
    ) {
        layer?.backgroundColor = NSColor(palette.softFillStrong).cgColor
        layer?.borderColor = NSColor(palette.subtleStroke).cgColor
        layer?.borderWidth = 1
        placeholderLabel.textColor = NSColor(palette.secondaryText)

        if currentAttachment != attachment || currentResolvedURL != resolvedURL {
            let loadedImage = resolvedURL.flatMap { NSImage(contentsOf: $0) }
            imageView.image = loadedImage
            let hasImage = loadedImage != nil
            imageView.isHidden = !hasImage
            placeholderLabel.isHidden = hasImage
            currentIntrinsicSize = loadedImage?.size ?? inferredSize(from: attachment)
            currentAttachment = attachment
            currentResolvedURL = resolvedURL
        }
        isHidden = false

        _ = updateAvailableWidth(availableWidth)
    }

    @discardableResult
    func updateAvailableWidth(_ availableWidth: CGFloat) -> Bool {
        guard !isHidden else { return false }
        let previousHeight = heightConstraint.constant
        let targetWidth = max(1, availableWidth.rounded(.down))
        let nextHeight = Self.displayHeight(for: currentIntrinsicSize, availableWidth: targetWidth)
        if abs(nextHeight - previousHeight) > 0.5 {
            heightConstraint.constant = nextHeight
            return true
        }
        return false
    }

    func reset() {
        imageView.image = nil
        imageView.isHidden = true
        placeholderLabel.isHidden = true
        heightConstraint.constant = 0
        currentAttachment = nil
        currentResolvedURL = nil
        currentIntrinsicSize = NSSize(width: 1, height: 1)
        isHidden = true
    }

    private func inferredSize(from attachment: MessageAttachment) -> NSSize {
        let width = attachment.pixelWidth.map(CGFloat.init) ?? 1
        let height = attachment.pixelHeight.map(CGFloat.init) ?? width
        return NSSize(width: width, height: height)
    }

    private static func displayHeight(for intrinsicSize: NSSize, availableWidth: CGFloat) -> CGFloat {
        let maxDisplayWidth = max(1, availableWidth)
        if intrinsicSize.width > 0, intrinsicSize.height > 0 {
            let scaledHeight = maxDisplayWidth * intrinsicSize.height / intrinsicSize.width
            return min(max(120, scaledHeight), 420)
        }
        return 240
    }

    #if DEBUG
        var hasLoadedImageForTesting: Bool {
            imageView.image != nil
        }

        var showsPlaceholderForTesting: Bool {
            !placeholderLabel.isHidden
        }

        var renderedHeightForTesting: CGFloat {
            renderedHeight
        }
    #endif
}

#if DEBUG
    extension MessageBodyTextView {
        var codeBlockBackgroundFramesForTesting: [NSRect] {
            codeBlockLayouts.map(\.backgroundFrame)
        }
    }

    extension MessageTableView {
        // swiftlint:disable identifier_name
        var scrollOriginYForTesting: CGFloat {
            scrollView.contentView.bounds.origin.y
        }

        var isLiveScrollingForTesting: Bool {
            isLiveScrolling
        }

        var pendingPinnedRowHeightInvalidationsCountForTesting: Int {
            pendingPinnedRowHeightInvalidations.count
        }

        func setScrollOriginYForTesting(_ y: CGFloat) {
            guard let documentView = scrollView.documentView else { return }
            let maxY = max(0, documentView.frame.height - scrollView.contentView.bounds.height)
            let target = NSPoint(x: 0, y: min(max(0, y), maxY))
            scrollView.contentView.scroll(to: target)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func triggerPinnedStateUpdateForTesting() {
            updatePinnedState()
        }

        func simulateLiveScrollStartForTesting() {
            handleWillStartLiveScroll()
        }

        func simulateLiveScrollEndForTesting() {
            handleDidEndLiveScroll()
        }

        @discardableResult
        func prepareCellForTesting(row: Int) -> MessageTableCellView? {
            guard tableView.numberOfColumns > 0 else { return nil }
            guard row >= 0, row < tableView.numberOfRows else { return nil }
            return testingCellForRow(row)
        }

        func visibleCellForTesting(row: Int) -> MessageTableCellView? {
            guard tableView.numberOfColumns > 0 else { return nil }
            guard row >= 0, row < tableView.numberOfRows else { return nil }
            return testingCellForRow(row)
        }

        private func testingCellForRow(_ row: Int) -> MessageTableCellView? {
            if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? MessageTableCellView {
                return cell
            }
            guard let runtime else { return nil }
            guard row >= 0, row < rows.count else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("MessageTableCellView.testing")
            let cell = MessageTableCellView(identifier: identifier)
            cell.configure(
                row: rows[row],
                runtime: runtime,
                availableWidth: effectiveAvailableWidth(),
                theme: theme,
                container: container,
                owningTableView: tableView,
                rowIndex: row,
                messageTableView: self
            )
            return cell
        }
        // swiftlint:enable identifier_name
    }

    extension MessageTableCellView {
        // swiftlint:disable identifier_name
        var hasRenderControllerForTesting: Bool {
            renderController != nil
        }

        var renderControllerCurrentPlainTextForTesting: String? {
            renderController?.currentOutput?.plainText
        }

        func shouldApplyOutputForTesting(
            plainText: String,
            observedRow: MessageTableView.RowModel
        ) -> Bool {
            let output = MessageRenderOutput(
                attributedString: NSAttributedString(string: plainText),
                plainText: plainText,
                diagnostics: []
            )
            return validatedRowForOutput(output, observedRow: observedRow) != nil
        }

        var cachedIntrinsicHeightForTesting: CGFloat? {
            bodyTextView.cachedIntrinsicHeight
        }

        var attributedStringForTesting: NSAttributedString {
            guard let storage = bodyTextView.textStorage else { return NSAttributedString() }
            return NSAttributedString(attributedString: storage)
        }

        var bodyTextAlignmentForTesting: NSTextAlignment {
            bodyTextView.alignment
        }

        var contentContainerFrameForTesting: NSRect {
            contentContainer.frame
        }

        var streamingDisplayedLengthForTesting: Int {
            streamingDisplayedLength
        }

        var streamingUpdateAssignmentCountForTesting: Int {
            streamingUpdateAssignmentsForTesting
        }

        var attachmentPreviewVisibleForTesting: Bool {
            !attachmentPreviewView.isHidden
        }

        var attachmentPreviewHasImageForTesting: Bool {
            attachmentPreviewView.hasLoadedImageForTesting
        }

        var attachmentPreviewShowsPlaceholderForTesting: Bool {
            attachmentPreviewView.showsPlaceholderForTesting
        }

        var attachmentPreviewRenderedHeightForTesting: CGFloat {
            attachmentPreviewView.renderedHeightForTesting
        }

        var debugButtonVisibleForTesting: Bool {
            !debugButton.isHidden
        }
        // swiftlint:enable identifier_name
    }
#endif

// swiftlint:enable file_length type_body_length
