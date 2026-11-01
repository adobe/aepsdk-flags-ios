# API usage

This page describes the public APIs of the Flags extension and how to handle their results and errors.

- [Extension version](#extension-version)
- [Evaluation context](#evaluation-context)
- [isFeatureEnabled](#isfeatureenabled)
- [getFeature](#getfeature)
- [FeatureEvaluationResult](#featureevaluationresult)
- [Custom identity](#custom-identity)
- [Handling errors](#handling-errors)

## Extension version

Returns the version of the Flags extension.

### Swift

```swift
static var extensionVersion: String
static func flagExtensionVersion() -> String
```

```swift
let version = Flag.extensionVersion
```

### Objective-C

```objc
@property (class, nonatomic, readonly, copy) NSString *extensionVersion;
+ (NSString *)flagExtensionVersion;
```

```objc
NSString *version = [AEPMobileFlag extensionVersion];
```

## Evaluation context

Every evaluation call takes a `FeatureEvaluationContext` (`AEPFeatureEvaluationContext` in Objective-C). The context holds the attributes that the targeting rules of your flags use, such as a region or an app version. Each attribute has a name and a list of string values.

Rules:

- Build the context with `FeatureEvaluationContext.builder()`, then call `withAttributes(_:)` and `build()`.
- Use attribute names and values that match the targeting rules you defined in Experience Flags.
- Call `withAttributes(_:)` at most once per builder. A second call raises an `NSInvalidArgumentException`, which terminates the app.
- To evaluate without attributes, call `build()` without calling `withAttributes(_:)`, or pass `nil` or an empty dictionary.
- A built context can't be changed. You can reuse it for several calls.
- Don't put user identities in the context. The extension reads identities from Identity for Edge Network. See [Custom identity](#custom-identity).

### Swift

```swift
let context = FeatureEvaluationContext.builder()
    .withAttributes([
        "region": ["US"],
        "appVersion": ["3.2.0"]
    ])
    .build()
```

### Objective-C

```objc
AEPFeatureEvaluationContext *context = [[[AEPFeatureEvaluationContext builder]
    withAttributes:@{
        @"region": @[@"US"],
        @"appVersion": @[@"3.2.0"]
    }]
    build];
```

## isFeatureEnabled

Checks whether a feature is enabled for the current user.

The result is `true` when the feature exists, the user matches its targeting rules, and the user isn't in a control group. Otherwise, the result is `false`.

### Swift

```swift
static func isFeatureEnabled(
    _ featureKey: String,
    evaluationContext: FeatureEvaluationContext,
    completion: @escaping (Bool) -> Void,
    errorCallback: ((AEPError) -> Void)?
)

static func isFeatureEnabled(
    _ featureKey: String,
    evaluationContext: FeatureEvaluationContext,
    completion: @escaping (Bool) -> Void
)
```

```swift
Flag.isFeatureEnabled("new-checkout", evaluationContext: context) { isEnabled in
    DispatchQueue.main.async {
        if isEnabled {
            showNewCheckout()
        } else {
            showDefaultCheckout()
        }
    }
} errorCallback: { _ in
    DispatchQueue.main.async {
        showDefaultCheckout()
    }
}
```

### Objective-C

```objc
+ (void)isFeatureEnabled:(NSString *)featureKey
       evaluationContext:(AEPFeatureEvaluationContext *)evaluationContext
              completion:(void (^)(BOOL))completion
           errorCallback:(void (^ _Nullable)(enum AEPError))errorCallback;

+ (void)isFeatureEnabled:(NSString *)featureKey
       evaluationContext:(AEPFeatureEvaluationContext *)evaluationContext
              completion:(void (^)(BOOL))completion;
```

```objc
[AEPMobileFlag isFeatureEnabled:@"new-checkout"
              evaluationContext:context
                     completion:^(BOOL isEnabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (isEnabled) {
            [self showNewCheckout];
        } else {
            [self showDefaultCheckout];
        }
    });
} errorCallback:^(enum AEPError error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showDefaultCheckout];
    });
}];
```

## getFeature

Returns the details of a feature for the current user, including the feature metadata and the variant the user is assigned to.

`getFeature` calls the completion with a result only when the feature is served to the user: the feature exists, the user matches its targeting rules, and the user isn't in a control group (feature-group or feature-level). Otherwise the feature is **not served**: the completion is called with `nil`. This is a normal outcome, **not an error**, and the error callback isn't called. The error callback runs only for genuine failures, such as an empty feature key, missing configuration, a failed evaluation, an unreadable response, or a timeout.

> **Behavior change:** earlier versions called the error callback with `AEPError.unexpected` when a feature wasn't served. If your app treated that error as "feature missing", handle `nil` in the completion instead.

| Situation | `isFeatureEnabled` | `getFeature` |
| --- | --- | --- |
| The feature applies to the user | `true` | Completion with a `FeatureEvaluationResult` |
| No feature has this key | `false` | Completion with `nil` |
| The user doesn't match the targeting rules | `false` | Completion with `nil` |
| The user is in a control group | `false` | Completion with `nil` |

Show your default experience when the result is `nil`, and also when the error callback runs.

### Swift

```swift
static func getFeature(
    _ featureKey: String,
    evaluationContext: FeatureEvaluationContext,
    completion: @escaping (FeatureEvaluationResult?) -> Void,
    errorCallback: ((AEPError) -> Void)?
)

static func getFeature(
    _ featureKey: String,
    evaluationContext: FeatureEvaluationContext,
    completion: @escaping (FeatureEvaluationResult?) -> Void
)
```

```swift
Flag.getFeature("new-checkout", evaluationContext: context) { result in
    DispatchQueue.main.async {
        guard let result else {
            showDefaultCheckout()
            return
        }
        showNewCheckout(metadata: result.meta)
    }
} errorCallback: { _ in
    DispatchQueue.main.async {
        showDefaultCheckout()
    }
}
```

### Objective-C

```objc
+ (void)getFeature:(NSString *)featureKey
 evaluationContext:(AEPFeatureEvaluationContext *)evaluationContext
        completion:(void (^)(AEPFeatureEvaluationResult * _Nullable))completion
     errorCallback:(void (^ _Nullable)(enum AEPError))errorCallback;

+ (void)getFeature:(NSString *)featureKey
 evaluationContext:(AEPFeatureEvaluationContext *)evaluationContext
        completion:(void (^)(AEPFeatureEvaluationResult * _Nullable))completion;
```

```objc
[AEPMobileFlag getFeature:@"new-checkout"
        evaluationContext:context
               completion:^(AEPFeatureEvaluationResult * _Nullable result) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (result == nil) {
            [self showDefaultCheckout];
            return;
        }
        [self showNewCheckoutWithMetadata:result.meta];
    });
} errorCallback:^(enum AEPError error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showDefaultCheckout];
    });
}];
```

## FeatureEvaluationResult

`getFeature` returns a `FeatureEvaluationResult` (`AEPFeatureEvaluationResult` in Objective-C).

| Property | Type | Description |
| --- | --- | --- |
| `id` | `Int` | The feature ID |
| `key` | `String` | The feature key |
| `featureGroupKey` | `String?` | The key of the feature group that contains the feature |
| `meta` | `String?` | The metadata configured for the feature, as text. The extension doesn't parse it. If your metadata is JSON, decode it in your app. |
| `analyticsParam` | `AnalyticsParam?` | Identifiers of the feature and the user's variant |

`AnalyticsParam` (`AEPAnalyticsParam` in Objective-C):

| Property | Type | Description |
| --- | --- | --- |
| `featureGroupId` | `Int` | The feature group ID |
| `featureId` | `Int` | The feature ID |
| `variantId` | `String?` | The variant the user is assigned to. `nil` when the feature isn't part of an experiment. |

For a feature that doesn't belong to a feature group, `featureGroupKey` and `featureGroupId` contain placeholder values. Don't use them in your app logic.

## Custom identity

The extension uses an identity to assign each user to a variant consistently. It reads identities from Identity for Edge Network. You don't pass identities in the evaluation context.

- **Default**: users are assigned by their Experience Cloud ID (ECID), which Identity for Edge Network creates automatically.
- **Custom identity namespace**: if a flag is set to assign users by a custom identity namespace, set an identity in that namespace with Identity for Edge Network before you evaluate the flag.

### Swift

```swift
import AEPEdgeIdentity

let identityMap = IdentityMap()
identityMap.add(
    item: IdentityItem(id: "user-123", authenticatedState: .authenticated, primary: false),
    withNamespace: "CRMID"
)
Identity.updateIdentities(with: identityMap)
```

### Objective-C

```objc
@import AEPEdgeIdentity;

AEPIdentityMap *identityMap = [[AEPIdentityMap alloc] init];
AEPIdentityItem *item = [[AEPIdentityItem alloc] initWithId:@"user-123"
                                         authenticatedState:AEPAuthenticatedStateAuthenticated
                                                    primary:NO];
[identityMap addItem:item withNamespace:@"CRMID"];
[AEPMobileEdgeIdentity updateIdentities:identityMap];
```

Rules:

- **Namespace matching**: the namespace you set must match the namespace configured on the flag exactly, including uppercase and lowercase letters.
- **Several identities in the namespace**: the extension uses the identity marked as primary. If none is marked as primary, it uses the first one.
- **Missing identity**: the call doesn't fail. Instead, the user is assigned to a variant at random for the current app session only. After the app restarts, the same user can be assigned to a different variant. Set the identity as soon as you know it, before you evaluate flags that use it.

## Handling errors

### Always use the error callback

Use the overloads that take an `errorCallback`. With the overloads that don't take one, nothing is called when an error occurs, so your app never gets a result.

When the error callback runs, show your default experience.

### Callback thread

The completion and the error callback run on a background thread, never on the main thread. Switch to the main thread before you update the UI, as the examples on this page do.

The one exception: if the feature key is empty, the error callback runs right away, on the thread that made the call.

### Timeout

Each call waits up to 10 seconds for a result. If no result arrives in time, the error callback runs with `AEPError.callbackTimeout`.

### Errors

| Error (Swift / Objective-C) | Cause |
| --- | --- |
| `AEPError.callbackTimeout` / `AEPErrorCallbackTimeout` | No result within 10 seconds. This usually happens when the SDK configuration hasn't loaded yet or the flag definitions are still downloading. |
| `AEPError.unexpected` / `AEPErrorUnexpected` | The feature key is empty, a required configuration value is missing, the flag definitions couldn't be downloaded, or the evaluation failed.  A feature that isn't served to the user isn't an error. See [getFeature](#getfeature). |

### First launch and offline behavior

- The extension downloads flag definitions each time the app launches. It keeps them in memory only.
- Calls made before the download finishes wait for it. If the download takes longer than the timeout, the call reports `AEPError.callbackTimeout`.
- If the download fails, the extension retries a few times. When the device is offline, this can take more than a minute. During that time, calls report `AEPError.callbackTimeout`.
- If every attempt fails, all calls report `AEPError.unexpected` for the rest of the app session. The extension tries again when the SDK configuration is next updated, typically on the next app launch.
- While the app is in the foreground, the extension refreshes flag definitions periodically. See [Initialize the SDK](getting-started.md#initialize-the-sdk) for the lifecycle calls this depends on.
