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
import XCTest

class FeatureEvaluationContextTests: XCTestCase {
    func testBuild_emptyBuilder_attributesNil() {
        let context = FeatureEvaluationContext.builder().build()
        XCTAssertNil(context.attributes)
    }

    func testWithAttributes_setsAttributes() {
        let attrs = ["region": ["US", "EU"]]
        let context = FeatureEvaluationContext.builder().withAttributes(attrs).build()
        XCTAssertEqual(attrs, context.attributes)
    }

    // Calling `withAttributes` twice is not supported (builder throws on second call).

    func testWithAttributes_emptyMap_storedAsNil() {
        let context = FeatureEvaluationContext.builder().withAttributes([:]).build()
        XCTAssertNil(context.attributes)
    }

    func testWithAttributes_null_treatedAsEmpty() {
        let context = FeatureEvaluationContext.builder().withAttributes(nil).build()
        XCTAssertNil(context.attributes)
    }

    func testWithAttributes_freezesInputMap() {
        var mutable = ["region": ["US"]]
        let context = FeatureEvaluationContext.builder().withAttributes(mutable).build()

        mutable["platform"] = ["IOS"]

        XCTAssertEqual(["region": ["US"]], context.attributes)
        XCTAssertEqual(1, context.attributes?.count)
    }

    func testBuilder_withAttributes_allFieldsSet() {
        let attrs = ["tier": ["premium"]]
        let context = FeatureEvaluationContext.builder().withAttributes(attrs).build()
        XCTAssertEqual("premium", context.attributes?["tier"]?.first)
    }
}
