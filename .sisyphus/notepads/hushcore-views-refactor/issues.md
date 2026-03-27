# Issues — hushcore-views-refactor

## Known Risks
- Task 13 (ConversationLifecycle) is largest extraction (~1000+ lines) with many interdependencies
- Task 14 (SendPipeline) is most coupled — calls into Message Buckets, Conversation Lifecycle, RequestCoordinator
- Task 9 (Composer dedup) requires careful analysis of subtle differences between ComposerDock and QuickBarComposer

## Xcode pbxproj Updates
- Every new file requires both PBXFileReference AND PBXBuildFile entries
- Files must be added to correct group in project.pbxproj
- Deletion of HushCore/PerfTrace.swift may need pbxproj cleanup

## SwiftLint Considerations
- AppContainer has `// swiftlint:disable file_length type_body_length` at line 7
- This must be removed in Task 15 AFTER all extractions complete
- New files must stay under 600 lines (warning threshold)

## Pre-existing Test Failures (NOT caused by refactoring)
These tests fail BEFORE any refactoring started (confirmed by testing on HEAD~1):
- TailPrewarmTests/Tail prewarm only renders missing cache entries
- TailPrewarmTests/Cold conversation streaming completion uses one-shot final-message prewarm
Total: 4 issues in TailPrewarmTests suite (2 tests, 2 issues each)
These failures are ACCEPTABLE — do not treat them as regressions.
