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

/// Logical operators that combine child filters in a criteria tree.
enum FilterOperator {
    case and
    case or
    case negate
    case none

    /// Parse a wire code (e.g. `"and"`, `"&&"`, `"not"`). Returns `.none` for unknown / empty input.
    static func from(code: String?) -> FilterOperator {
        guard let raw = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return .none }
        switch raw {
        case "and", "&", "&&":      return .and
        case "or", "|", "||":       return .or
        case "not", "negate", "!":  return .negate
        default:                    return .none
        }
    }
}
