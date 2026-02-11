## Learnings

(Append-only. Do not overwrite.)

### Wave 1 Implementation (2026-02-17)

**A. RequestCoordinator UI Flush Throttle**
- Used `applyUIFlush()` helper to avoid code duplication between immediate and deferred flush paths.
- `flushPendingUIUpdate()` resets `lastUIFlush` to nil (not `ContinuousClock.now`) since streaming is ending.
- First delta (message creation via `.append`) is NOT throttled — only subsequent updates go through throttle.
- Wired `flushPendingUIUpdate()` into all 4 terminal paths: `stop()`, `completeActiveRequest()`, `failActiveRequest()`, `cancelAll()`.

**B. ChatScrollStage Scroll Throttle**
- Used `Date.now` (not `ContinuousClock`) because SwiftUI view layer + `@State` + `Date` is simpler.
- Only throttles `.onChange(of: container.messages.last?.content)` — other scroll triggers remain immediate.

**C. rankByID Cache**
- Moved from local `let` in `body` to `@State` recomputed in `handleMessagesChanged` and `resetForConversationSwitch`.
- **Critical**: `@State` dictionary directly in complex SwiftUI body causes "compiler unable to type-check". Fix: capture to local `let cachedRanks = rankByID` before `ForEach`.

**D. Test Design**
- `uiFlushCountIsBounded` uses polling with `Set<String>` for distinct content versions — keeps production code clean.
- `RapidDeltaProvider` (synchronous deltas) and `SlowDeltaProvider` (10ms delay) are both `actor` with `swiftlint:disable async_without_await` for protocol conformance.

**Build/Lint Notes**
- `make fmt` exits error 2 on clean `dev` branch due to pre-existing `AppContainer.swift` function_body_length error (127 > 120).
- ChatScrollStage.swift has pre-existing `type_body_length` and `function_parameter_count` warnings.

