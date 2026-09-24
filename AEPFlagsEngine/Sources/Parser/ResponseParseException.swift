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

/// Thrown when a combined response body cannot be parsed.
/// Wrapped as ``FlagClientError`` at the HTTP boundary
struct ResponseParseException: Error {

    let message: String
    let underlying: Error?

    init(_ message: String, underlying: Error? = nil) {
        self.message = message
        self.underlying = underlying
    }
}

extension ResponseParseException: LocalizedError {
    var errorDescription: String? { message }
}
