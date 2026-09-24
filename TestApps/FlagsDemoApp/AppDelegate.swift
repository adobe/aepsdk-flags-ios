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

import AEPCore
import AEPEdge
import AEPFlags
import AEPEdgeIdentity
import AEPLifecycle
import AEPServices
import SwiftUI
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        MobileCore.setLogLevel(.trace)

        // Register foundation extensions first; Flag last (depends on Configuration + Identity shared state).
        let extensions = [
            Identity.self,
            Edge.self,
            Lifecycle.self,
            Flag.self
        ]

        MobileCore.registerExtensions(extensions) {
            MobileCore.configureWith(appId: FlagDemoFetchConfig.launchAppId)

            DispatchQueue.main.async {
                if application.applicationState != .background {
                    MobileCore.lifecycleStart(additionalContextData: nil)
                }
            }
        }

        return true
    }
}
