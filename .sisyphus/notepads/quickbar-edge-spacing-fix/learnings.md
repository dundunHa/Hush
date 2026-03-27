## [2026-03-28] Task 1: outer-edge helper
- transcript readable width formula: QuickBarPanelReleaseMetrics.width - (sm+2+xs)*2 = 680
- outer-edge gap measurement: visibleTextFrameForTesting in cell coords maps 1:1 to table coords when cell fills full column width
- smoke test compiled and ran; accessors work
- pbxproj uses PBXFileSystemSynchronizedRootGroup for HushTests — no manual pbxproj edits needed, just drop files into directory
- QuickBarTranscriptMetrics is private to MessageTableView.swift, so test file derives readable width independently using same constants
- hostCell default width set to transcriptReadableWidth (680) to match actual QB transcript area
- T4 finding: existing getters are sufficient for outer-edge gap; bodyFrameForTesting and visibleTextFrameForTesting are already converted into cell coordinates, so left/right outer gaps can be derived directly with minX / containerWidth-maxX when the cell fills the container

## Task 2: Compact Plain-Text Symmetry Tests

### Result: GREEN (not RED as expected)

Both short-text and long-text compact plain-text symmetry tests **passed** on the current codebase.

### Actual Gap Values

| Scenario | assistantBodyLeftGap | userBodyRightGap | bodyDelta | assistantVisibleLeftGap | userVisibleRightGap | visDelta |
|----------|---------------------|------------------|-----------|------------------------|--------------------|---------| 
| Short text ("Hello!" / "你好世界!") | 20.0 | 20.0 | 0.0 | 20.0 | 20.0 | 0.0 |
| Long text ("The quick brown fox..." / "敏捷的棕色狐狸...") | 20.0 | 20.0 | 0.0 | 20.0 | 20.0 | 0.0 |

### Key Findings

- Both body frame and visible text frame layers show **perfect symmetry** (delta = 0.0) for compact plain-text at `transcriptReadableWidth` = 680
- The outer-edge gap is exactly 20.0pt on both sides for both roles
- This means the asymmetry issue (if any) is NOT in the compact plain-text path when cells are hosted at `transcriptReadableWidth`
- The asymmetry may only manifest in the full panel context (with SwiftUI padding layers) rather than at the cell level
- `hostCell(cell, width: transcriptReadableWidth)` creates a direct NSWindow -> NSView -> cell hierarchy, which bypasses SwiftUI padding layers

### Test Infrastructure Notes

- `hostCell` returns `(window, host, container)` — cell fills full container width
- `makeQBRow` creates a minimal `RowModel` with no attachments (triggers compact path)
- `outerEdgeTolerance = 1.0` — tests assert `abs(delta) <= 1.0`

## Task 3: Waiting-State & FullWidth Symmetry Tests

### Result: Both GREEN (not RED)

Both waiting-state and fullWidth/rich markdown symmetry tests **passed** on the current codebase.

### Actual Gap Values

| Scenario | assistantBodyLeftGap | userBodyRightGap | bodyDelta | assistantVisibleLeftGap | userVisibleRightGap | visDelta |
|----------|---------------------|------------------|-----------|------------------------|--------------------|---------| 
| Waiting-state (streaming, empty) | 20.0 | 20.0 | 0.0 | 20.0 | 20.0 | 0.0 |
| FullWidth (markdown heading) | 20.0 | 20.0 | 0.0 | 20.0 | 20.0 | 0.0 |

### Key Findings

- **All three presentation modes** (.leadingColumn, .fullWidth, .trailingColumn) produce identical 20.0pt outer-edge gaps — **perfect symmetry**
- Waiting-state placeholder (`isStreaming: true, content: ""`) has visible text (the placeholder text from `RenderConstants.assistantWaitingPlaceholder`), so visible-text-frame assertions ran (not skipped)
- Waiting-state visible text width = 220.0pt; user visible text width = 220.0pt
- FullWidth assistant visible text width = 339.0pt (wider due to heading + paragraph); user visible text width = 220.0pt
- The asymmetry issue, if it exists, does NOT manifest at the cell level when cells are hosted at `transcriptReadableWidth`
- The consistent 20.0pt gap across all modes suggests the contentContainer inset is the same for all presentation modes in QuickBarMessageCellView

### Presentation Mode Routing Verified

- `makeQBRow(content: "", role: .assistant, isStreaming: true)` → `isAssistantWaitingState` true → `.leadingColumn`
- `makeQBRow(content: "# Title\n...", role: .assistant)` → `containsStableMarkdownCue` true → `.fullWidth`
- `makeQBRow(content: "...", role: .user)` → `.trailingColumn`

## Task 5 insight: corner-radius visual bias

- After adding real `MessageTableView.apply(..., surfaceStyle: .quickBar)` tests, compact and waiting-state paths still remained geometrically symmetric.
- The remaining discrepancy is most plausibly a visual effect from `QuickBarPanelView` using `transcriptCornerRadius = 28` with `transcriptTopPadding = 4`.
- The first user row sits too high inside the rounded top corner zone, making the right border appear optically closer than the left border seen by lower assistant rows.
- Mitigation applied: increase `QuickBarPanelView.Layout.transcriptTopPadding` from `HushSpacing.xs` to `HushSpacing.md` so first rows render below the strongest corner curvature.
