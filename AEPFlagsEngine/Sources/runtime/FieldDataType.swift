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

/// Field data types used by the rule engine to parse and compare values in criteria.
enum FieldDataType: String {
    case string             = "STRING"
    case integer            = "INTEGER"
    case long               = "LONG"
    case decimal            = "DECIMAL"
    case boolean            = "BOOLEAN"
    case date               = "DATE"
    case dateTime           = "DATE_TIME"
    case version            = "VERSION"
    case ipAddr             = "IP_ADDR"
    case listString         = "LIST_STRING"
    case listInteger        = "LIST_INTEGER"
    case listLong           = "LIST_LONG"
    case listDecimal        = "LIST_DECIMAL"
    case listVersion        = "LIST_VERSION"
    case setString          = "SET_STRING"
    case setInteger         = "SET_INTEGER"
    case mapStringString    = "MAP_STRING_STRING"
    case filter             = "FILTER"

    /// Parse the wire representation. Falls back to `.string` for unknown / empty input.
    static func from(_ value: String?) -> FieldDataType {
        guard let raw = value, !raw.isEmpty else { return .string }
        return FieldDataType(rawValue: raw.uppercased()) ?? .string
    }

    /// `true` if this type is one of the `LIST_*` variants.
    var isList: Bool {
        switch self {
        case .listString, .listInteger, .listLong, .listDecimal, .listVersion: return true
        default: return false
        }
    }

    /// `true` if this type is numeric (`INTEGER`, `LONG`, `DECIMAL`).
    var isNumeric: Bool {
        switch self {
        case .integer, .long, .decimal: return true
        default: return false
        }
    }

    /// `true` if this type represents a date / date-time.
    var isDate: Bool {
        switch self {
        case .date, .dateTime: return true
        default: return false
        }
    }
}
