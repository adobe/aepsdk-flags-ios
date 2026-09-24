# Adobe Experience Platform — Flags extension for iOS

Feature flag extension for iOS. Provides `getFeature` and `isFeatureEnabled` backed by the Flags engine (compiled in-repo alongside the extension into the **`AEPFlags`** module) and Adobe Experience Platform Mobile SDK.

**Distribution:** this repository is the source of truth. Customers integrate **`AEPFlags`** either via Swift Package Manager (source, resolved directly from this repo's `Package.swift` at a release tag) or by downloading the prebuilt **`AEPFlags.xcframework`** attached to a GitHub Release. There is no CDN and no separate private repository — everything ships from here.

## Requirements

- Xcode 15+
- Swift 5.3+
- iOS 12+

## Customer installation

### Option A — Swift Package Manager (source)

In Xcode: **File → Add Package Dependencies**, add this repository's URL, and select a release version. Also add [AEPCore](https://github.com/adobe/aepsdk-core-ios) (includes AEPLifecycle), [AEPEdge](https://github.com/adobe/aepsdk-edge-ios), and [AEPEdgeIdentity](https://github.com/adobe/aepsdk-edgeidentity-ios).

### Option B — Prebuilt XCFramework

Download `AEPFlags.xcframework.zip` from this repository's [Releases](../../releases) page, unzip it, and drag `AEPFlags.xcframework` into your project (or reference it from a local `Package.swift` as a `binaryTarget`). You still need AEPCore/AEPEdge/AEPEdgeIdentity as separate dependencies either way — the merged framework deliberately does not embed them (see [Extension binary isolation](#extension-binary-isolation) below).

```swift
import AEPFlags
```

## Register the extension

```swift
import AEPCore
import AEPEdge
import AEPEdgeIdentity
import AEPLifecycle
import AEPFlags

MobileCore.registerExtensions([
    Identity.self,
    Edge.self,
    Lifecycle.self,
    Flag.self
]) {
    MobileCore.configureWith(appId: "<your-launch-app-id>")
    MobileCore.lifecycleStart(additionalContextData: nil)
}
```

### Objective-C

```objc
@import AEPCore;
@import AEPEdge;
@import AEPEdgeIdentity;
@import AEPLifecycle;
@import AEPFlags;

[AEPMobileCore registerExtensions:@[
    AEPMobileEdgeIdentity.class,
    AEPMobileEdge.class,
    AEPMobileLifecycle.class,
    AEPMobileFlag.class
] completion:^{
    [AEPMobileCore configureWithAppId:@"<your-launch-app-id>"];
    [AEPMobileCore lifecycleStart:nil];
}];
```

## Public API

```swift
let context = FeatureEvaluationContext.builder()
    .withAttributes(["region": ["US"]])
    .build()

Flag.getFeature("my-feature", evaluationContext: context) { result in
    // result is nil when no matching feature
}

Flag.isFeatureEnabled("my-feature", evaluationContext: context) { enabled in
    print(enabled)
}
```

Identity for evaluation is read automatically from **AEPEdgeIdentity** shared state (register Edge Identity before Flag). You do not pass visitor IDs in `FeatureEvaluationContext`.

### Evaluation context

`FeatureEvaluationContext` carries **targeting attributes** only. Identity for bucketing is resolved automatically on each evaluation.

```swift
let context = FeatureEvaluationContext.builder()
    .withAttributes([
        "locale": ["en_US"],
        "platform": ["IOS"],
        "appVersion": ["3.0.0"]
    ])
    .build()
```

| Attribute | Example values |
| --------- | -------------- |
| `locale` | `["en_US"]`, `["fr_FR"]` |
| `platform` | `["IOS"]` |
| `appVersion` | `["3.0.0"]` |
| `deviceType` | `["phone"]`, `["tablet"]` |

## Exposure batching (Edge)

Feature evaluations can emit **exposure events** to Adobe Experience Platform Edge as `decisioning.propositionDisplay` events. The extension **batches** these for efficient impression counting.

| Condition | Queued for exposure? |
| --------- | -------------------- |
| Feature evaluated with exposure analytics metadata | **Yes** (includes control cohort) |
| Feature not found | No |
| Feature without exposure analytics metadata | No |

API responses return **immediately**. Edge dispatch is **asynchronous** and flushes when:

1. **20 unique features** are queued in the current window (immediate flush), **or** a **150-second one-shot timer** fires while pending work exists (whichever comes first).
2. App moves to **background** (Lifecycle `pause`) — timer cancelled, pending events flushed.
3. App returns to **foreground** (Lifecycle `start`) — timer restarts if work remains.
4. Extension **shutdown** (best-effort async flush).

**Register AEPLifecycle** so background/foreground transitions reach the Flags extension. Without Lifecycle, exposures still queue but may only flush on batch size, timer, or process exit.

Duplicate evaluations of the same feature in one flush window produce **one** Edge event with an aggregated impression count. Profile identity on exposure events is merged by **Edge + Edge Identity** when Edge processes the event.

## Configuration (Data Collection)

Keys align with the cross-platform Flags extension configuration contract.

| Key | Required | Description |
|-----|----------|-------------|
| `experienceCloud.org` | Yes | IMS organization ID (standard AEP key) |
| `flags.clientId` | Yes | Flags client / application ID |
| `flags.sandbox` | Yes | AEP sandbox name |
| `edge.domain` | No | Host-only Edge domain for feature fetches (no scheme or path). Defaults to `edge.adobedc.net` when omitted or blank |

Example (programmatic config for local testing):

```swift
MobileCore.updateConfigurationWith(configDict: [
    "experienceCloud.org": "<imsOrg>",
    "flags.clientId": "<clientId>",
    "flags.sandbox": "<sandbox>",
    "edge.domain": "edge.adobedc.net"
])
```

### Extension identity (EventHub)

| Property | Value |
|----------|-------|
| Extension name | `com.adobe.flags` |
| Event type | `com.adobe.eventType.flags` |
| Edge exposure XDM | `decisioning.propositionDisplay` (`_experience.decisioning`) |

Contributor module layout, test commands, and manual validation: **[AEPFlags/README.md](AEPFlags/README.md)**.

## Architecture

`FlagsEngine` (the feature evaluation engine) lives in this repo as source, under `AEPFlagsEngine/`. It compiles as its own internal Swift Package Manager target — never published or importable on its own — that the `AEPFlags` target depends on internally. There is exactly one public product: `AEPFlags`.

| Location | Swift module | Published as its own product? |
|----------|--------------|--------------------------------|
| `AEPFlagsEngine/Sources` | `FlagsEngine` | No — internal target only |
| `AEPFlags/Sources` | `AEPFlags` | Yes — the only public product |

Customers **`import AEPFlags` only**. They never import or depend on `FlagsEngine` directly, whether they consume this repo via SPM (source) or the prebuilt XCFramework — both paths produce the same single public module.

## Development

Build and test from the repo root (single `Package.swift`, no separate manifest for customers vs. development):

```bash
make build
make test
make build-extension-xcf   # builds AEPFlags.xcframework (extension + engine, from source)
```

`make build-extension-xcf` runs `Scripts/build-extension-xcframework.sh`, which archives the extension and engine together via `xcodebuild archive` and links them into one merged `AEPFlags.xcframework` — no download step, no external artifact. See [Extension binary isolation](#extension-binary-isolation) below for why AEPCore is deliberately kept out of that merged binary.

## Release

Two artifacts are published per release, both built from this repo's source:

1. **SPM (source)** — tag the repo (e.g. `1.0.0`); consumers resolve `AEPFlags` directly via `Package.swift` at that tag. No additional build step needed on Adobe's side.
2. **XCFramework (binary)** — run `./Scripts/build-extension-xcframework.sh`, then attach the resulting `build/AEPFlags.xcframework.zip` to the GitHub Release for that tag.

```bash
./Scripts/build-extension-xcframework.sh
# attach build/AEPFlags.xcframework.zip to the GitHub Release
```

Optional Adobe Distribution signing for the XCFramework: pass a `.p12` + password (`AEP_DISTRIBUTION_P12_PATH`/`AEP_DISTRIBUTION_P12_PASSWORD` env vars, or as script arguments). Without them, the device slice ships unsigned and the simulator slice is ad-hoc signed.

### Extension binary isolation

The merged **`AEPFlags`** XCFramework **must not** embed AEPCore or AEPServices. Customers add AEPCore separately (via SPM or the XCFramework path); if the binary also contained AEPCore, the app would load **two copies** of `Event` → **`EXC_BAD_ACCESS`** in extension handlers. `Scripts/build-extension-xcframework.sh` builds AEPFlags's and FlagsEngine's object files into static archives containing *only* their own code, force-loads both into one dynamic framework, and leaves AEPCore/AEPServices symbols undefined so the customer app's own copy resolves them at link time.

The public **`AEPFlags.swiftinterface`** **must not** `import FlagsEngine`. Extension sources use `@_implementationOnly import FlagsEngine` so the engine module boundary stays invisible to consumers — customers see and import `AEPFlags` only, regardless of which distribution path they use.

**Customer responsibilities:**

- Add `AEPFlags` via SPM or the XCFramework release asset
- Add AEPCore, AEPEdge, AEPEdgeIdentity, AEPLifecycle as separate dependencies
- Register extensions and `MobileCore.configureWith(appId:)` as documented
- Use a compatible AEPCore **major** version (currently `5.8.0+` in the build manifest)

## Demo app

`TestApps/FlagsDemoApp` is a sample app that uses the root **`Package.swift`** (source, local SPM reference) plus AEPCore/Edge/Identity/Lifecycle from GitHub. It exercises `import AEPFlags` with Mobile Core + Edge — the same integration path a real customer would use. Populate `FlagDemoFetchConfig` locally with your Launch app ID, feature keys, and evaluation context before running.

```bash
make customer-demo          # open in Xcode
make customer-demo-build    # CI-style build
```

Extension development uses root **`Package.swift`** directly (`make build`, `make test`) — no separate Xcode project required.

### Objective-C sample

`TestApps/FlagsDemoAppObjC` mirrors the Swift demo: two tabs (**Flags** batch `isFeatureEnabled`, **Get Feature** JSON `getFeature`), editable evaluation context, and the same `FlagDemoFetchConfig` placeholders. It uses the root **`Package.swift`** via local SPM — same integration path as `FlagsDemoApp`.

```bash
make objc-demo          # open FlagsDemoAppObjC in Xcode
make objc-demo-build    # CI-style build
```

Populate `FlagDemoFetchConfig` locally with your Launch app ID, feature keys, and evaluation context before running.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
