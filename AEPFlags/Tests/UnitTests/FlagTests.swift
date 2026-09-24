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

@testable import AEPFlags
import AEPCore
import ObjectiveC
import XCTest

class FlagTests: XCTestCase {
    func testExtensionVersion() {
        // Assert the public API surfaces the single-sourced version constant (not a hardcoded
        // literal), so the update-version workflow can bump it without breaking this test.
        XCTAssertEqual(FlagConstants.extensionVersion, Flag.flagExtensionVersion())
        XCTAssertEqual(FlagConstants.extensionVersion, Flag.extensionVersion)
    }

    func testExtensionType() {
        XCTAssertTrue(Flag.self is Extension.Type)
    }

    func testObjectiveCClassName() {
        XCTAssertEqual(String(cString: class_getName(Flag.self)), "AEPMobileFlag")
    }
}
