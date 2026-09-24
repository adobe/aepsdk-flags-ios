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

@testable import AEPFlags
@testable import AEPCore
import Foundation

final class MockFlagIdentityFetcher: FlagIdentityFetcher {
    var identityMap: [String: [[String: Any]]]?
    var identityReady = true
    private(set) var warmUpCallCount = 0

    func fetchIdentityMap(extensionRuntime: ExtensionRuntime, event: Event) -> [String: [[String: Any]]]? {
        _ = extensionRuntime
        _ = event
        return identityMap
    }

    func isIdentityReady(extensionRuntime: ExtensionRuntime, event: Event) -> Bool {
        _ = extensionRuntime
        _ = event
        return identityReady
    }

    func warmUp() {
        warmUpCallCount += 1
    }
}
