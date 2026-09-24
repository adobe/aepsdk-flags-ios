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

/// Error thrown during SDK operations after initialization (feature evaluation or API call failed).
/// Bridges to `NSError` for Objective-C consumers.
public enum FlagClientError: Error, LocalizedError, CustomNSError {

    case notInitialized
    case operationFailed(message: String, underlying: Error?)
    case invalidArgument(message: String)
    case networkFailure(statusCode: Int, message: String)

    public static var errorDomain: String { "com.adobe.marketing.flags.client" }

    public var errorCode: Int {
        switch self {
        case .notInitialized:    return 1001
        case .operationFailed:   return 1002
        case .invalidArgument:   return 1003
        case .networkFailure:    return 1004
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Client is not initialized or has been closed"
        case .operationFailed(let message, _):
            return message
        case .invalidArgument(let message):
            return message
        case .networkFailure(let statusCode, _):
            return "Request failed with status: \(statusCode)"
        }
    }

    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [:]
        if let desc = errorDescription { info[NSLocalizedDescriptionKey] = desc }
        if case .operationFailed(_, let underlying) = self, let underlying = underlying {
            info[NSUnderlyingErrorKey] = underlying
        }
        return info
    }
}
