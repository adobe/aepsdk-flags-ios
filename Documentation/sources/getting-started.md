# Getting started

This page explains how to add the Flags extension to an iOS app and initialize it.

- [Requirements](#requirements)
- [Set up Data Collection](#set-up-data-collection)
- [Install the extension](#install-the-extension)
- [Initialize the SDK](#initialize-the-sdk)
- [Configuration reference](#configuration-reference)

## Requirements

- iOS 12.0 or later
- Xcode 16 or later, with Swift 5.7 or later <!-- TODO: verify the minimum Xcode version that can consume the released XCFramework -->
- These Adobe Experience Platform Mobile SDK extensions:

| Extension | Module | Minimum version |
| --- | --- | --- |
| Mobile Core | `AEPCore` | 5.8.0 |
| Lifecycle | `AEPLifecycle` | Same version as `AEPCore` |
| Edge Network | `AEPEdge` | 5.0.2 |
| Identity for Edge Network | `AEPEdgeIdentity` | 5.0.0 |

## Set up Data Collection

Your mobile property in Data Collection must have these extensions installed and configured:

- Mobile Core
- Lifecycle
- Edge Network, with a datastream
- Identity for Edge Network
- Adobe Flags

To install and configure the Adobe Flags extension:

<!-- TODO: verify the Data Collection UI labels in these steps -->

1. In Data Collection, select **Tags**, then open your mobile property.
2. Select **Extensions** > **Catalog**, search for **Adobe Flags**, then select **Install**.
3. In the extension settings, enter the **Sandbox** and the **Application ID**, then select **Save**.
4. Publish your changes.
5. Select **Environments**, then copy the **Environment File ID** of the environment you want to use. You use this ID when you initialize the SDK.

## Install the extension

The extension supports two installation methods: Swift Package Manager and XCFramework.

### Swift Package Manager

In Xcode:

1. Select **File** > **Add Package Dependencies**.
2. Enter the package URL: `https://github.com/adobe/aepsdk-flags-ios.git`
3. For the version rule, select **Exact Version** and enter the latest version from the [releases page](https://github.com/adobe/aepsdk-flags-ios/releases).
4. Add the `AEPFlags` library to your app target.
5. Add the Adobe packages that the extension depends on, and add their libraries to your app target:
   - `https://github.com/adobe/aepsdk-core-ios.git`: `AEPCore`, `AEPLifecycle`, and `AEPServices`
   - `https://github.com/adobe/aepsdk-edge-ios.git`: `AEPEdge`
   - `https://github.com/adobe/aepsdk-edgeidentity-ios.git`: `AEPEdgeIdentity`

If your project uses a `Package.swift` file, add the dependencies there instead. Replace `<latest-version>` with the latest version from the [releases page](https://github.com/adobe/aepsdk-flags-ios/releases).

```swift
dependencies: [
    .package(url: "https://github.com/adobe/aepsdk-flags-ios.git", exact: "<latest-version>"),
    .package(url: "https://github.com/adobe/aepsdk-core-ios.git", .upToNextMajor(from: "5.8.0")),
    .package(url: "https://github.com/adobe/aepsdk-edge-ios.git", .upToNextMajor(from: "5.0.2")),
    .package(url: "https://github.com/adobe/aepsdk-edgeidentity-ios.git", .upToNextMajor(from: "5.0.0"))
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "AEPFlags", package: "aepsdk-flags-ios"),
            .product(name: "AEPCore", package: "aepsdk-core-ios"),
            .product(name: "AEPLifecycle", package: "aepsdk-core-ios"),
            .product(name: "AEPServices", package: "aepsdk-core-ios"),
            .product(name: "AEPEdge", package: "aepsdk-edge-ios"),
            .product(name: "AEPEdgeIdentity", package: "aepsdk-edgeidentity-ios")
        ]
    )
]
```

### XCFramework

1. From the [releases page](https://github.com/adobe/aepsdk-flags-ios/releases), download `AEPFlags-<version>.xcframework.zip` and unzip it.
2. Download the XCFrameworks that the extension depends on from each repository's releases page. Use versions that meet the minimums in [Requirements](#requirements).
   - [aepsdk-core-ios releases](https://github.com/adobe/aepsdk-core-ios/releases): `AEPCore`, `AEPServices`, `AEPLifecycle`, and `AEPRulesEngine`
   - [aepsdk-edge-ios releases](https://github.com/adobe/aepsdk-edge-ios/releases): `AEPEdge`
   - [aepsdk-edgeidentity-ios releases](https://github.com/adobe/aepsdk-edgeidentity-ios/releases): `AEPEdgeIdentity`
3. In Xcode, select your app target, then open **General** > **Frameworks, Libraries, and Embedded Content**.
4. Add `AEPFlags.xcframework` and all the dependent XCFrameworks.
5. Set each framework to **Embed & Sign**.

No additional build settings are required.

## Initialize the SDK

### Recommended: `MobileCore.initialize`

`MobileCore.initialize(appId:)` registers the Adobe extensions that are part of your app, configures the SDK with your Environment File ID, and tracks app lifecycle automatically.

`MobileCore.initialize` does not register the Flags extension automatically. Register it with `MobileCore.registerExtensions` first, then call `MobileCore.initialize`. Call both once, as early as possible, for example in `application(_:didFinishLaunchingWithOptions:)`. You may see a log message that an extension cannot be registered multiple times; it refers to the Configuration extension and is harmless.

#### Swift

```swift
import AEPCore
import AEPFlags
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        MobileCore.registerExtensions([Flag.self])
        MobileCore.initialize(appId: "<your-environment-file-id>")
        return true
    }
}
```

#### Objective-C

```objc
@import AEPCore;
@import AEPFlags;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [AEPMobileCore registerExtensions:@[AEPMobileFlag.class] completion:nil];
    [AEPMobileCore initializeWithAppId:@"<your-environment-file-id>" completion:nil];
    return YES;
}
```

### Alternative: register extensions manually

If you register extensions yourself, register all of them and configure the SDK in the completion handler.

With manual registration, the SDK doesn't track app lifecycle for you. Call `MobileCore.lifecycleStart` when the app enters the foreground and `MobileCore.lifecyclePause` when it enters the background. The Flags extension depends on these calls:

- **Foreground (`lifecycleStart`)**: if the app was in the background, the extension downloads the latest flag definitions and resumes refreshing them periodically.
- **Background (`lifecyclePause`)**: the extension stops refreshing flag definitions and sends any pending [exposure data](exposure-analytics.md). Without this call, pending exposure data is sent only when a batch fills up or a timer fires, and it's lost if the app is terminated first.

#### Swift

```swift
import AEPCore
import AEPEdge
import AEPEdgeIdentity
import AEPFlags
import AEPLifecycle
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        MobileCore.registerExtensions([
            Lifecycle.self,
            Edge.self,
            AEPEdgeIdentity.Identity.self,
            Flag.self
        ]) {
            MobileCore.configureWith(appId: "<your-environment-file-id>")
            DispatchQueue.main.async {
                if application.applicationState != .background {
                    MobileCore.lifecycleStart(additionalContextData: nil)
                }
            }
        }
        return true
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        MobileCore.lifecycleStart(additionalContextData: nil)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        MobileCore.lifecyclePause()
    }
}
```

`AEPEdgeIdentity.Identity` is the Identity for Edge Network extension. Use the module-qualified name so it isn't confused with `AEPIdentity.Identity` if your app also uses that module.

#### Objective-C

```objc
@import AEPCore;
@import AEPEdge;
@import AEPEdgeIdentity;
@import AEPFlags;
@import AEPLifecycle;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [AEPMobileCore registerExtensions:@[
        AEPMobileLifecycle.class,
        AEPMobileEdge.class,
        AEPMobileEdgeIdentity.class,
        AEPMobileFlag.class
    ] completion:^{
        [AEPMobileCore configureWithAppId:@"<your-environment-file-id>"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (application.applicationState != UIApplicationStateBackground) {
                [AEPMobileCore lifecycleStart:nil];
            }
        });
    }];
    return YES;
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    [AEPMobileCore lifecycleStart:nil];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [AEPMobileCore lifecyclePause];
}
```

If your app uses scenes, make the `lifecycleStart` call in `sceneWillEnterForeground(_:)` and the `lifecyclePause` call in `sceneDidEnterBackground(_:)` of your scene delegate instead.

### Get the extension version

#### Swift

```swift
let version = Flag.extensionVersion
```

#### Objective-C

```objc
NSString *version = [AEPMobileFlag extensionVersion];
```

## Configuration reference

The extension reads these values from the SDK configuration. You set them in Data Collection; you don't need to set them in code.

<!-- TODO: verify which Adobe Flags extension setting in Data Collection maps to each key -->

| Key | Set by | Required | Description |
| --- | --- | --- | --- |
| `experienceCloud.org` | Mobile Core | Yes | Your organization ID |
| `flags.sandbox` | Adobe Flags (**Sandbox**) | Yes | The sandbox that contains your flags |
| `flags.clientId` | Adobe Flags (**Application ID**) | Yes | The application that your flags belong to |
| `edge.domain` | Edge Network | No | The Edge Network domain. Defaults to `edge.adobedc.net` |

If a required value is missing, every evaluation call reports an error. If the configuration hasn't loaded yet, evaluation calls wait for it, up to the response timeout. For details, see [Handling errors](api-usage.md#handling-errors).

## Next steps

- [API usage](api-usage.md)
- [Exposure analytics](exposure-analytics.md)
