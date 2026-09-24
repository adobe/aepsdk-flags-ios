# AEPFlags module (`AEPFlags/Sources`)

Contributor guide for the iOS **Experience Flags** extension (EventHub name `com.adobe.flags`).

**Integrators:** setup, Data Collection configuration, public API, and exposure batching behavior are documented in the [repository README](../README.md). This file covers module internals, build commands, and tests only.

---

## Source layout

| Component | File | Responsibility |
| --------- | ---- | ---------------- |
| Public API | `Flag+PublicAPI.swift`, `FeatureEvaluationContext.swift` | App-facing evaluation APIs |
| Extension | `Flag.swift` | EventHub registration, readiness gating, lifecycle |
| Client | `FlagClientManager.swift` | Flags SDK lifecycle, request handling, exposure queue wiring |
| Exposure queue | `Internal/FeatureExposureQueue.swift` | Batch, dedup, one-shot timer, lifecycle pause/resume, shutdown |
| Key generation | `Internal/ExposureEventIdGenerator.swift` | Queue dedup keys and Edge correlation IDs |
| Edge dispatch | `FlagEdgeHandler.swift` | `decisioning.propositionDisplay` XDM build + Edge events |
| Evaluation mapping | `Internal/FeatureResultMapper.swift` | `isEnabledFeatureResult()`, `featureResultToMap()` |
| Response mapping | `Internal/FlagResponseMapper.swift` | Public API payload parsing |
| Identity | `Internal/EdgeIdentityFetcher.swift`, `Internal/IdentityMapMarshaller.swift` | Edge Identity shared state → engine `identityMap` |
| Request factory | `Internal/GetFeatureRequestFactory.swift` | Engine `GetFeatureRequest` builder |
| Constants | `FlagConstants.swift` | Extension name, Edge keys, exposure queue tuning |

Exposure batching rules (flush triggers, enqueue eligibility) are defined in product terms in the [repository README — Exposure batching](../README.md#exposure-batching-edge). Implementation constants:

```swift
// FlagConstants.ExposureQueue
batchSize = 20
flushIntervalMs = 150_000  // 150 seconds
```

---

## Build and test

From the **repository root**:

```bash
make build
make test                    # SPM unit tests (iOS Simulator)
make build-extension-xcf     # merged customer XCFramework
make customer-demo           # open demo app in Xcode
```

| Test class | Focus |
| ---------- | ----- |
| `FeatureExposureQueueTests` | Batch, timer, dedup, shutdown |
| `ExposureEventIdGeneratorTests` | Key formats, control cohort, null guards |
| `FlagEdgeHandlerTests` | XDM schema, correlation ID, display count |
| `FlagClientManagerTests` | Enqueue gating, lifecycle flush, evaluation path |
| `FlagExtensionTests` | Readiness gating, Edge Identity, lifecycle, API paths, concurrent callers |
| `EdgeIdentityFetcherTests`, `IdentityMapMarshallerTests` | Identity pipeline |
| `FeatureResultMapperTests`, `FlagResponseMapperTests` | Response / enabled-state mapping |
| `GetFeatureRequestFactoryTests` | `identityMap` pass-through |

Test helpers (not shipped in the XCFramework):

| Path | Helpers |
| ---- | ------- |
| `Tests/UnitTests/TestHelpers/` | `MockFlagsMobileClient`, `ExposureQueueTestSupport`, `ExposureTestAssertions`, `MockFlagIdentityFetcher` |

---

## Manual validation (demo app)

Install `TestApps/FlagsDemoApp` with valid Data Collection config (Core, Lifecycle, Edge, Edge Identity, Flags). In Xcode console, filter `Flags` and Edge extension logs.

1. Call `getFeature` / `isFeatureEnabled` repeatedly for the **same** flag — expect **one** Edge exposure per flush window with aggregated display count (background the app to flush).
2. Evaluate **different** features in the same feature group — expect **separate** Edge events.
3. Background the app (Home / lifecycle pause) — pending exposures should flush immediately.

```bash
make customer-demo
```

---

## Related documentation

- [Repository README](../README.md) — development and architecture
