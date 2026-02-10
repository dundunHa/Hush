# HushSettings Module

> JSON persistence layer for app settings.

## Purpose

HushSettings provides file-based persistence for `AppSettings` using JSON encoding. It handles directory creation, atomic writes, and graceful fallback to defaults when no file exists.

## Dependencies

- `HushCore` — `AppSettings` and its nested types

## Public Types

| Type | Kind | File | Description |
|------|------|------|-------------|
| `JSONSettingsStore` | struct | `JSONSettingsStore.swift` | Read/write `AppSettings` to a JSON file |

### JSONSettingsStore API

```swift
init(fileURL: URL)
static func defaultStore() -> JSONSettingsStore
func load() throws -> AppSettings
func save(_ settings: AppSettings) throws
```

- **`defaultStore()`** — resolves to `~/Library/Application Support/Hush/settings.json`
- **`load()`** — returns `.default` if the file does not exist; throws on decode failure
- **`save(_:)`** — creates parent directories, writes atomically with pretty-printed sorted-keys JSON

## Persistence Policy

The raw `JSONSettingsStore` is a synchronous save/load API. The **debounced persistence policy** is implemented in `AppContainer` (HushApp module):

1. **Trailing debounce** — settings mutations schedule a 1-second debounce; rapid mutations coalesce into a single write.
2. **Lifecycle flush** — `flushSettings()` is called on app background/inactive transitions, immediately persisting the latest dirty snapshot and canceling any pending debounce.
3. **Failure visibility** — save failures set `statusMessage` and keep `isDirty = true` for retry on next debounce or flush.

## Test Coverage

Tests in `Tests/HushCoreTests/`:
- `SettingsStoreTests.swift` — load returns default when file missing, save/load round-trip
- `DebouncedPersistenceTests.swift` — rapid mutation coalescing, spaced writes, flush force-save, flush cancels debounce, flush no-op when clean
- `PersistenceFailureTests.swift` — failure keeps dirty, retry on next flush, error surfaced in status
