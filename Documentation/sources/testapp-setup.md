# Test app setup

The repository includes two sample apps that call the Flags extension, one in Swift and one in Objective-C. Use them to try the API against your own flags.

| App | Project | Open with |
| --- | --- | --- |
| Swift (SwiftUI) | `TestApps/FlagsDemoApp/FlagsDemoApp.xcodeproj` | `make customer-demo` |
| Objective-C (UIKit) | `TestApps/FlagsDemoAppObjC/FlagsDemoAppObjC.xcodeproj` | `make objc-demo` |

## Set up

1. Complete [Set up Data Collection](getting-started.md#set-up-data-collection) and copy the **Environment File ID**.
2. Open the sample app's `FlagDemoFetchConfig` file (`.swift` for the Swift app, `.h` and `.m` for the Objective-C app).
3. Set `environmentFileId` to your Environment File ID.
4. Add your flags to `knownFeatures`. Each entry is a feature key from your sandbox. The list is empty by default.
5. Select a simulator or device and run the app.

## What to expect

- If `environmentFileId` is empty, the app doesn't configure the SDK and shows a status message that explains what to set.
- If `knownFeatures` is empty, the fetch actions are disabled and the app shows a message instead of a feature list.
- **Custom Identity** sets and removes an identity in the Edge Identity extension, so you can test flags that are targeted or cohorted by a custom namespace. See [Custom identity](api-usage.md#custom-identity).

## Build from the command line

```bash
make customer-demo-build
make objc-demo-build
```
