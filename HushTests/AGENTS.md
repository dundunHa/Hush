# HushTests

Swift Testing test suite. 43 test files covering all modules. Factory-method setup, in-memory databases, stub networking.

## Structure

```
Tests organized by module, named <Module>Tests.swift:
  AppContainerTests.swift              # Bootstrap, DI, forTesting()
  RequestCoordinatorTests.swift        # Multi-conversation lifecycle
  RequestSchedulerTests.swift          # Pure-function scheduling logic
  ChatPersistenceCoordinatorTests.swift# Streaming flush + finalization
  GRDB*RepositoryTests.swift           # One per repository (7+ files)
  DatabaseManagerTests.swift           # Migrations, WAL mode
  KeychainAdapterTests.swift           # Provider credential persistence + resolver behavior
  CredentialResolverTests.swift        # Persisted API key validation
  SSEParserTests.swift                 # Server-sent events parsing
  HTTPClientTests.swift                # URLSession + StubURLProtocol
  OpenAIProviderTests.swift            # Provider request/response
  MarkdownToAttributedTests.swift      # Rich text conversion
  MathSegmenterTests.swift             # LaTeX extraction
  RenderControllerTests.swift          # Two-phase render lifecycle
  RenderingFixtures.swift              # Shared test data (Markdown/Math nested enums)
  PreviewSupport.swift                 # SwiftUI preview fixtures
```

## Where to Look

| Task | File |
|------|------|
| Add tests for new repository | Create `GRDB*RepositoryTests.swift`, use `DatabaseManager.inMemory()` |
| Add tests for new provider | Follow `OpenAIProviderTests.swift` pattern with `StubURLProtocol` |
| Add rendering test cases | Add fixtures to `RenderingFixtures.swift`, test in `MarkdownToAttributedTests.swift` |
| Integration test with AppContainer | Use `AppContainer.forTesting(...)` with injected deps |
| HTTP stubbing | Use `StubURLProtocol` — register response, create `URLSession` with custom config |

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
