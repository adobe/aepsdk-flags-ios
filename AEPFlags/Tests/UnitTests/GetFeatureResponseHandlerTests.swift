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

@testable import AEPCore
@testable import AEPFlags
import XCTest

/// Verifies the public getFeature contract: "not served" is success with nil, genuine failures are errors,
/// and exactly one callback fires.
class GetFeatureResponseHandlerTests: XCTestCase {
    private func response(_ data: [String: Any]?) -> Event {
        Event(
            name: FlagConstants.EventNames.flagsResponse,
            type: FlagConstants.EventType.flags,
            source: FlagConstants.EventSource.responseContent,
            data: data
        )
    }

    /// Returns (completion calls, results, error calls).
    private func run(_ event: Event?) -> (completions: Int, result: FeatureEvaluationResult?, errors: [AEPError]) {
        var completions = 0
        var result: FeatureEvaluationResult?
        var errors: [AEPError] = []
        GetFeatureResponseHandler.handle(
            responseEvent: event,
            completion: { completions += 1; result = $0 },
            errorCallback: { errors.append($0) }
        )
        return (completions, result, errors)
    }

    // Not served (unknown key, unmatched targeting, group control, feature-level control) all produce
    // an empty response from the request handler.
    func testNotServed_emptyResponse_successNil_calledOnce_noError() {
        for data in [[:], nil] as [[String: Any]?] {
            let out = run(response(data))
            XCTAssertEqual(1, out.completions)
            XCTAssertNil(out.result)
            XCTAssertTrue(out.errors.isEmpty)
        }
    }

    func testServed_mapsFields() {
        let out = run(response([
            FlagConstants.EventDataKeys.feature: [
                FlagConstants.EventDataKeys.id: 7,
                FlagConstants.EventDataKeys.key: "dark-mode",
                FlagConstants.EventDataKeys.featureGroupKey: "fg",
                FlagConstants.EventDataKeys.meta: "m",
                FlagConstants.EventDataKeys.analyticsParam: [
                    FlagConstants.EventDataKeys.featureGroupId: 1,
                    FlagConstants.EventDataKeys.featureId: 7,
                    FlagConstants.EventDataKeys.variantId: "v1"
                ]
            ]
        ]))
        XCTAssertEqual(1, out.completions)
        XCTAssertTrue(out.errors.isEmpty)
        XCTAssertEqual(7, out.result?.id)
        XCTAssertEqual("dark-mode", out.result?.key)
        XCTAssertEqual("fg", out.result?.featureGroupKey)
        XCTAssertEqual("m", out.result?.meta)
        XCTAssertEqual(7, out.result?.analyticsParam?.featureId)
        XCTAssertEqual("v1", out.result?.analyticsParam?.variantId)
    }

    func testErrorMarker_error_noCompletion() {
        let out = run(response([FlagConstants.EventDataKeys.responseError: AEPError.unexpected.rawValue]))
        XCTAssertEqual(0, out.completions)
        XCTAssertEqual(1, out.errors.count)
    }

    func testMalformedPayload_error_noCompletion() {
        // Missing required `id`, and a null key (the legacy control payload shape) are both malformed.
        let malformed: [[String: Any]] = [
            [FlagConstants.EventDataKeys.key: "k"],
            [FlagConstants.EventDataKeys.id: -1, FlagConstants.EventDataKeys.key: NSNull()]
        ]
        for featureMap in malformed {
            let out = run(response([FlagConstants.EventDataKeys.feature: featureMap]))
            XCTAssertEqual(0, out.completions)
            XCTAssertEqual(1, out.errors.count)
        }
    }

    func testTimeout_error_noCompletion() {
        let out = run(nil)
        XCTAssertEqual(0, out.completions)
        XCTAssertEqual(1, out.errors.count)
    }
}
