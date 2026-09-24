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

/// Expression-validator registry — maps `FieldDataType` values to their
/// `IExpressionValidator` implementations. Registry of
/// `ExpressionValidator` (which doubles as both registry and factory).
enum ExpressionValidator: CaseIterable {

    case date
    case dateTime

    /// `FieldDataType` this validator handles.
    var dataType: FieldDataType {
        switch self {
        case .date:     return .date
        case .dateTime: return .dateTime
        }
    }

    /// Underlying validator implementation.
    var instance: IExpressionValidator {
        switch self {
        case .date, .dateTime: return DateExpressionValidator()
        }
    }

    /// Validator for `dataType`, or `nil` if unsupported.
    static func validator(for dataType: FieldDataType) -> ExpressionValidator? {
        for validator in Self.allCases where validator.dataType == dataType {
            return validator
        }
        return nil
    }

    /// `true` if expression validation is supported for `dataType`.
    static func supports(_ dataType: FieldDataType) -> Bool {
        return validator(for: dataType) != nil
    }

    /// Parse an expression via the underlying validator.
    func parseExpression(_ expression: Any) throws -> Any {
        return try instance.parseExpression(String(describing: expression))
    }
}
