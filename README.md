# Adobe Experience Platform Flags Mobile Extension

[![SPM](https://img.shields.io/github/v/release/adobe/aepsdk-flags-ios?label=SPM&logo=apple&logoColor=white&color=orange&sort=semver)](https://github.com/adobe/aepsdk-flags-ios/releases)
[![License](https://img.shields.io/github/license/adobe/aepsdk-flags-ios)](LICENSE)

## About this project

The Adobe Experience Platform Flags mobile extension (`AEPFlags`) lets an iOS app evaluate feature flags that you manage in Experience Flags. It works with the [Adobe Experience Platform Mobile SDK](https://developer.adobe.com/client-sdks) and sends feature exposure data to Adobe Experience Platform through the Edge Network extension.

## Before you start

### Requirements

- iOS 12.0 or later
- Xcode 16 or later, with Swift 5.7 or later <!-- TODO: verify the minimum Xcode version that can consume the released XCFramework -->
- AEPCore 5.8.0 or later
- A mobile property in Data Collection with these extensions installed and configured:
  - Mobile Core
  - Lifecycle
  - Edge Network, with a datastream
  - Identity for Edge Network
  - Adobe Flags

### Install and configure the Adobe Flags extension in Data Collection

<!-- TODO: verify the Data Collection UI labels in these steps -->

1. In Data Collection, select **Tags**, then open your mobile property.
2. Select **Extensions** > **Catalog**, search for **Adobe Flags**, then select **Install**.
3. In the extension settings, enter the **Sandbox** and the **Application ID**, then select **Save**.
4. Publish your changes.
5. Select **Environments**, then copy the **Environment File ID** of the environment you want to use.

## Installation

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

## Development

To run the sample app:

1. Open `TestApps/FlagsDemoApp/FlagsDemoApp.xcodeproj` in Xcode, or run `make customer-demo`.
2. In `TestApps/FlagsDemoApp/FlagDemoFetchConfig.swift`, set `environmentFileId` to your Environment File ID and add your feature keys to `knownFeatures`.
3. Select the `FlagsDemoApp` scheme and an iOS Simulator, then select **Run**.

An Objective-C version of the sample app is in `TestApps/FlagsDemoAppObjC`. For details, see [Sample app setup](Documentation/sources/testapp-setup.md).

For build and test commands, see the [contributor guide](AEPFlags/README.md).

## Documentation

See the [documentation index](Documentation/README.md).

## Related Projects

| Project | Description |
| --- | --- |
| [Core for iOS](https://github.com/adobe/aepsdk-core-ios) | The Mobile Core, Services, Lifecycle, and Identity extensions |
| [Edge Network for iOS](https://github.com/adobe/aepsdk-edge-ios) | The Edge Network extension |
| [Identity for Edge Network for iOS](https://github.com/adobe/aepsdk-edgeidentity-ios) | The Identity for Edge Network extension |

## Contributing

Contributions are welcome. Read the [contributing guidelines](.github/CONTRIBUTING.md) for more information.

## Licensing

This project is licensed under the Apache V2 License. See [LICENSE](LICENSE) for more information.
