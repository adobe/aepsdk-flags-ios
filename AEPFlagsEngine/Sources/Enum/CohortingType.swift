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

/// Cohorting strategies supported by the policy evaluator.
@objc(AEPMobileCohortingType)
public enum CohortingType: Int {
    case sticky
    case ecid

    /// Wire value as understood by the Edge service. Wire value for the Edge service.
    public var rawString: String {
        switch self {
        case .sticky: return "STICKY"
        case .ecid:   return "ECID"
        }
    }

    /// Parse a wire string (case-insensitive) into a `CohortingType`. Returns `nil` for unknown values.
    public static func from(_ value: String?) -> CohortingType? {
        guard let v = value?.uppercased() else { return nil }
        switch v {
        case "STICKY": return .sticky
        case "ECID":   return .ecid
        default:       return nil
        }
    }
}
