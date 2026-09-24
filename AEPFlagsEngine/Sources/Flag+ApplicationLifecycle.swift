/*
 Copyright 2026 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import Foundation

#if canImport(UIKit)

public extension Flag {

    /// Starts forwarding `UIApplication` background / foreground notifications to ``setAppState(_:)``.
    /// Retain the returned ``FlagApplicationLifecycleBinding`` until you call ``FlagApplicationLifecycleBinding/stop()``
    /// or release it (``FlagApplicationLifecycleBinding`` stops in `deinit`).
    /// For SwiftUI-only lifecycle (`scenePhase`), call ``setAppState(_:)`` when the scene moves
    /// between active and background if you prefer not to use `UIApplication` notifications.
    func bindApplicationLifecycle(notificationCenter: NotificationCenter = .default) -> FlagApplicationLifecycleBinding {
        let binding = FlagApplicationLifecycleBinding(flag: self, notificationCenter: notificationCenter)
        binding.start()
        return binding
    }
}

@objc public extension Flag {

    /// Objective-C: same as ``bindApplicationLifecycle(notificationCenter:)`` with the default notification center.
    @objc(bindApplicationLifecycleAndReturnBinding)
    func bindApplicationLifecycleAndReturnBinding() -> FlagApplicationLifecycleBinding {
        return bindApplicationLifecycle()
    }
}
#endif
