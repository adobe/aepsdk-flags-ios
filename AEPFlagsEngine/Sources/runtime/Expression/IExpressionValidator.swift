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

/// Common protocol implemented by every expression validator.
/// Implementations parse a dynamic
/// expression string and return the computed runtime value (type depends on the
/// validator — e.g. `DateExpressionValidator` returns an `Int64` epoch millis).
protocol IExpressionValidator {

    /// Parse `expression` and return the computed value.
    /// - Throws: `FlagClientError.invalidArgument` for empty / unsupported input.
    func parseExpression(_ expression: String) throws -> Any
}
