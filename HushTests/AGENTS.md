# HushTests

Swift Testing test suite. 77 test files covering all modules. Factory-method setup, in-memory databases, stub networking.

## Structure

```
Tests organized by module, named <Module>Tests.swift:
  AppContainer*Tests.swift              # Bootstrap, DI, forTesting(), catalog, persistence semantics, streaming (6 files)
  RequestCoordinator*Tests.swift        # Multi-conversation lifecycle, streaming flush, image gen, message trace, strict validation (5 files)
  RequestSchedulerTests.swift           # Pure-function scheduling logic
  ChatPersistenceCoordinatorTests.swift # Streaming flush + finalization
  GRDB*RepositoryTests.swift            # One per repository (Conversation, Message, ProviderConfig, ProviderCatalog, AgentPreset, etc.)
  DatabaseMigrationTests.swift          # Migrations, WAL mode, schema verification
  KeychainAdapterTests.swift            # Provider credential persistence (legacy compat)
  CredentialResolverTests.swift         # Persisted API key validation (in KeychainAdapterTests)
  SSEParserTests.swift                  # Server-sent events parsing
  HTTPClientTests.swift                 # URLSession + StubURLProtocol
  OpenAIProviderTests.swift             # Provider request/response (785 lines)
  OpenAIProviderImageGenerationTests.swift # DALL-E image generation
  MarkdownRenderingTests.swift          # Rich text conversion
  MathRenderCacheTests.swift            # Math render LRU cache
  LatexSegmentationTests.swift          # LaTeX extraction
  RenderController*Tests.swift          # Two-phase render lifecycle, scheduling
  CellCacheFirst*Tests.swift            # Cell cache rendering + streaming tests
  MessageTableView*Tests.swift          # Apply strategy, bottom inset, fast-track, scroll, height invalidation, prewarm, surface style (8 files)
  HotScene*Tests.swift                  # Pool, switch, controller streaming fast-path (4 files)
  TailFollowStateMachineTests.swift     # Auto-scroll state transitions
  QuickBar*Tests.swift                  # Configuration, routing, shortcut recording (3 files)
  ConversationSidebarViewPolicyTests.swift # Sidebar activity state resolution
  RenderingFixtures.swift               # Shared test data (Markdown/Math nested enums)
  SidebarPolicy.swift                   # Test utility for sidebar policy
```

## Where to Look

| Task | File |
|------|------|
| Add tests for new repository | Create `GRDB*RepositoryTests.swift`, use `DatabaseManager.inMemory()` |
| Add tests for new provider | Follow `OpenAIProviderTests.swift` pattern with `StubURLProtocol` |
| Add rendering test cases | Add fixtures to `RenderingFixtures.swift`, test in `MarkdownRenderingTests.swift` |
| Integration test with AppContainer | Use `AppContainer.forTesting(...)` with injected deps |
| HTTP stubbing | Use `StubURLProtocol` — register response, create `URLSession` with custom config |
| Quick Bar behavior tests | `QuickBarRoutingTests.swift`, `QuickBarConfigurationTests.swift` |
| Table view scroll/layout tests | `MessageTableView*Tests.swift` family |
| Image generation tests | `OpenAIProviderImageGenerationTests.swift`, `RequestCoordinatorImageGenerationTests.swift` |

## Conventions

- **Swift Testing only**: `import Testing`, `@Suite("...")`, `@Test("...")`, `#expect(...)`. Never XCTest.
- **Factory methods**: `makeRepo()`, `makeClient()`, `makeScheduler()` returning tuples — no `setUp()`/`tearDown()`.
- **In-memory DB**: `DatabaseManager.inMemory()` for every database test — isolated, disposable.
- **StubURLProtocol**: Register canned responses for HTTP tests. No real network calls.
- **Serialized suites**: Mark with `.serialized` trait when tests share mutable state.
- **Fixtures**: `RenderingFixtures` enum with nested `Markdown` and `Math` enums for shared test data.
- **Test naming**: Struct name matches module (`SSEParserTests`, not `TestSSEParser`). No `Test` prefix.

## Anti-Patterns

- **Never use XCTest** — `XCTAssert*`, `XCTestCase`, `setUp/tearDown` are all forbidden.
- **Never hit real network** — always `StubURLProtocol`.
- **Never share database state between tests** — each test gets fresh `inMemory()`.
- **Never import `Hush` without `@testable`** — internal access required.
