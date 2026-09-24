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
import XCTest
@testable import FlagsEngine

/// Shared HTTP request assertions for integration and cache tests.
enum ServiceRequestAssertions {

    static func assertFeatureRequest(_ request: URLRequest,
                                     clientId: String,
                                     expectedContextVersion: String?,
                                     expectedIfNoneMatch: String? = nil,
                                     expectedSdkVersion: String? = nil,
                                     file: StaticString = #file,
                                     line: UInt = #line) {
        guard let url = request.url else {
            XCTFail("Missing request URL", file: file, line: line)
            return
        }

        XCTAssertEqual(url.path, FlagConstants.FLAGS_FEATURE_PATH, file: file, line: line)

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(query[FlagConstants.Query.CLIENT_ID], clientId, file: file, line: line)
        XCTAssertTrue(query.keys.contains(FlagConstants.Query.SDK_VERSION),
                      "sdkVersion query param must always be present",
                      file: file, line: line)

        // The version is injected by the host extension; with no injection the key is present
        // but carries no value. Flatten String?? -> String? for comparison.
        let actualSdkVersion = query[FlagConstants.Query.SDK_VERSION] ?? nil
        XCTAssertEqual(actualSdkVersion, expectedSdkVersion, file: file, line: line)

        if expectedContextVersion == nil {
            XCTAssertNil(query[FlagConstants.Query.CONTEXT_VERSION], file: file, line: line)
        } else {
            XCTAssertEqual(query[FlagConstants.Query.CONTEXT_VERSION], expectedContextVersion, file: file, line: line)
        }

        if expectedIfNoneMatch == nil {
            XCTAssertNil(headerValue(request, field: FlagConstants.Headers.IF_NONE_MATCH), file: file, line: line)
        } else {
            XCTAssertEqual(headerValue(request, field: FlagConstants.Headers.IF_NONE_MATCH),
                           expectedIfNoneMatch,
                           file: file, line: line)
        }
    }

    private static func headerValue(_ request: URLRequest, field: String) -> String? {
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            if key.caseInsensitiveCompare(field) == .orderedSame {
                return value
            }
        }
        return nil
    }
}
