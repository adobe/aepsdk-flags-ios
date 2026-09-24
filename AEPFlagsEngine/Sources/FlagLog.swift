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
import os.log

/// Thin logging facade over `os.log`. Internal-only; not part of the public API.
enum FlagLog {

    private static let log = OSLog(subsystem: FlagConstants.EXTENSION_NAME, category: FlagConstants.LOG_TAG)

    @inline(__always)
    static func trace(_ message: @autoclosure () -> String,
                      file: StaticString = #fileID,
                      line: UInt = #line) {
        os_log("%{public}@", log: log, type: .debug, message())
    }

    @inline(__always)
    static func debug(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: log, type: .debug, message())
    }

    @inline(__always)
    static func info(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: log, type: .info, message())
    }

    @inline(__always)
    static func warning(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: log, type: .default, message())
    }

    @inline(__always)
    static func error(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: log, type: .error, message())
    }
}
