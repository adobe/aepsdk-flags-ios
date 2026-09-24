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
import AEPEdgeIdentity
import Foundation

/// Reads Edge Identity from XDM shared state for synchronous, event-ordered identity resolution.
final class EdgeIdentityFetcher: FlagIdentityFetcher {
    func fetchIdentityMap(extensionRuntime: ExtensionRuntime, event: Event) -> [String: [[String: Any]]]? {
        let result = getEdgeIdentitySharedState(extensionRuntime: extensionRuntime, event: event)

        guard result?.status == .set else {
            return nil
        }

        guard let stateValue = result?.value, !stateValue.isEmpty else {
            return nil
        }

        return IdentityMapMarshaller.fromXDMStateMap(stateValue)
    }

    func isIdentityReady(extensionRuntime: ExtensionRuntime, event: Event) -> Bool {
        let result = getEdgeIdentitySharedState(extensionRuntime: extensionRuntime, event: event)
        guard let result else {
            return true
        }
        return result.status == .set
    }

    func warmUp() {
        Identity.getIdentities { _, _ in }
    }

    private func getEdgeIdentitySharedState(extensionRuntime: ExtensionRuntime, event: Event?) -> SharedStateResult? {
        extensionRuntime.getXDMSharedState(
            extensionName: FlagConstants.EdgeIdentity.extensionName,
            event: event,
            barrier: false,
            resolution: .lastSet
        )
    }
}
