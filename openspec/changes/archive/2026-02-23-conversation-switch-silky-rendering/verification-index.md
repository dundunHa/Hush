# Verification Index (Requirement → Tests)

This index links each delta-spec requirement to primary automated test evidence.

## render-cache-conversation-protection

| Requirement | Primary test evidence |
|---|---|
| RenderCache capacity supports multi-conversation workloads | `HushTests/RenderCacheTests.swift`, `HushTests/RenderCacheProtectionTests.swift` |
| RenderCache provides conversation-aware eviction protection | `HushTests/RenderCacheProtectionTests.swift` |
| Switch-away prewarm populates RenderCache for adjacent conversations | `HushTests/SwitchAwayPrewarmTests.swift` |
| Idle prewarm maintains RenderCache for recently-visited conversations | `HushTests/IdlePrewarmTests.swift` |
| Startup prewarm covers expanded scope | `HushTests/AppContainerPersistenceSemanticsTests.swift` |
| Streaming-complete prewarm caches final assistant content | `HushTests/StreamingCompletePrewarmTests.swift` |
| Protection has bounded per-conversation capacity | `HushTests/RenderCacheProtectionTests.swift` |
| Protection lifecycle is tied to scene pool and conversation deletion | `HushTests/HotSceneSwitchTests.swift`, `HushTests/AppContainerPersistenceSemanticsTests.swift` |
| Window resize invalidates protection for stale widths | `HushTests/ResizeCacheCleanupTests.swift` |
| All RenderCache and prewarm access runs on @MainActor | `HushTests/IdlePrewarmTests.swift`, `HushTests/SwitchAwayPrewarmTests.swift` |

## cell-cache-first-rendering

| Requirement | Primary test evidence |
|---|---|
| Assistant message cell uses cached rich text when available | `HushTests/CellCacheFirstRenderingTests.swift` |
| SwiftUI MessageBubble achieves cache-first rendering via RenderController | `HushTests/RenderControllerSchedulingTests.swift` |

## hot-scene-pool

| Requirement | Primary test evidence |
|---|---|
| Hot scene pool maintains a bounded set of live conversation views | `HushTests/HotScenePoolTests.swift` |
| Switching to a pooled conversation uses visibility toggle | `HushTests/HotSceneSwitchTests.swift` |
| Switching to a non-pooled conversation creates or recycles a scene | `HushTests/HotSceneSwitchTests.swift`, `HushTests/HotScenePoolTests.swift` |
| Evicted scenes release resources cleanly | `HushTests/HotSceneSwitchTests.swift` |
| Hot scene pool can be disabled via feature flag | `HushTests/FeatureFlagFallbackTests.swift`, `HushTests/HotScenePoolTests.swift` |
| Empty conversations are deprioritized in pool eviction | `HushTests/HotScenePoolTests.swift` |

## multi-scene-render-scheduling

| Requirement | Primary test evidence |
|---|---|
| Render scheduler supports multi-tier conversation priority | `HushTests/MultiSceneSchedulerTests.swift` |
| Scene configuration is set atomically | `HushTests/MultiSceneSchedulerTests.swift` |
| Hidden scenes defer UI updates until visible | `HushTests/HiddenSceneDeferredUpdateTests.swift` |
| SwiftUI update propagation is isolated to active scene | `HushTests/HiddenSceneDeferredUpdateTests.swift`, `HushTests/HotSceneSwitchTests.swift` |
| Tail prewarm maintains render cache for hot scenes | `HushTests/TailPrewarmTests.swift`, `HushTests/StreamingCompletePrewarmTests.swift` |

## markdown-message-rendering

| Requirement | Primary test evidence |
|---|---|
| Rendering caches are bounded to protect memory | `HushTests/RenderCacheTests.swift`, `HushTests/RenderCacheProtectionTests.swift` |
| Conversation switch should prewarm a bounded set of recent conversations | `HushTests/SwitchAwayPrewarmTests.swift`, `HushTests/IdlePrewarmTests.swift`, `HushTests/HotSceneSwitchTests.swift` |
