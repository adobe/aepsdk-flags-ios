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
@testable import FlagsEngine

enum IdentityMapTestHelpers {

    static let defaultCohortingNamespace = CohortingType.ecid.rawString

    static func ecidBucketingParams() -> [String: Any] {
        [FlagConstants.JSONKeys.COHORTING_TYPE: defaultCohortingNamespace]
    }

    static func identityEntry(id: String?, primary: Bool?) -> [String: Any] {
        var entry: [String: Any] = [
            FlagConstants.IdentityMap.ENTRY_KEY_AUTHENTICATED_STATE: "ambiguous"
        ]
        if let id = id {
            entry[FlagConstants.IdentityMap.ENTRY_KEY_ID] = id
        }
        if let primary = primary {
            entry[FlagConstants.IdentityMap.ENTRY_KEY_PRIMARY] = primary
        }
        return entry
    }

    static func identityMap(namespace: String, id: String, primary: Bool = true) -> [String: [[String: Any]]] {
        [namespace: [identityEntry(id: id, primary: primary)]]
    }

    static func request(namespace: String, id: String) -> GetFeatureRequest {
        GetFeatureRequest.builder().identityMap(identityMap(namespace: namespace, id: id)).build()
    }

    static func request(identityMap: [String: [[String: Any]]]) -> GetFeatureRequest {
        GetFeatureRequest.builder().identityMap(identityMap).build()
    }
}
