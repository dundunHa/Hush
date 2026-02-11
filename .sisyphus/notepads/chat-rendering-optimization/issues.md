## Issues

(Append-only. Do not overwrite.)

## 2026-02-17 — Pre-existing LSP errors
- `HushTests/ChatScrollStageAutoScrollPolicyTests.swift` has 6 LSP errors:
  - `Type 'ChatScrollStage' has no member 'resolveCountChangeAutoScrollAction'`
  - `Cannot infer contextual base in reference to member 'assistant'` / 'user'
- These errors exist BEFORE any optimization work begins
- The function `resolveCountChangeAutoScrollAction` IS defined in `ChatScrollStage.swift:166` as `static func`
- The test file calls it as `ChatScrollStage.resolveCountChangeAutoScrollAction(...)` which should work
- This may be an LSP indexing issue or a build configuration problem
- MUST verify with `make test` whether these tests actually compile and pass

