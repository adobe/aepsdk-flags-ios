#!/usr/bin/env bash
#
# Copyright 2026 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.
#
# Run AEPFlagsTests and FlagsEngineTests on an iOS Simulator via Swift Package Manager.
# FlagsEngine is a local source target (see Package.swift) -- no CDN binary pin, no
# framework-embedding workaround needed; SPM links and packages everything automatically.
#
# AEPFlagsTests never touches the real AEPCore MobileCore EventHub (extension behavior is tested
# against a mock ExtensionRuntime -- see AEPFlags/Tests/UnitTests/TestHelpers/TestableExtensionRuntime.swift),
# so there is no EventHub-shutdown timing race to retry around here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

swift package resolve

DEST="$("./Scripts/resolve_ios_sim_dest.sh" "${1:-${DEST:-}}")"
DD="${ROOT}/.build/DerivedData"

# Wall-clock micro-benchmarks guard against algorithmic regressions in the hot evaluation path,
# but their absolute time budgets are only meaningful on dedicated developer hardware. Shared CI
# runners are virtualized and can be throttled 2-3x, so the same code intermittently blows the
# budget for reasons unrelated to the SDK. Skip them on CI (a live signal for local `make test`,
# not a hard gate on CI). `-skip-testing:` is keyed off `$CI`, which GitHub Actions sets in the
# runner shell -- reliable here, unlike an in-process env check the simulator test host never sees.
SKIP_PERF_ARGS=()
if [ "${CI:-}" = "true" ]; then
  echo "CI detected: skipping wall-clock performance tests (unreliable on shared runners)."
  SKIP_PERF_ARGS=(
    "-skip-testing:FlagsEngineTests/RuleProcessorStandaloneTests/testPerformanceTenThousandEvaluations"
    "-skip-testing:FlagsEngineTests/FilterTreeGeneratorTests/testPerformanceLocalEvaluation"
    "-skip-testing:FlagsEngineTests/FlagIntegrationTests/testPerformanceBenchmarkTenThousandEvaluations"
  )
fi

xcodebuild build-for-testing \
  -scheme AEPFlags \
  -destination "${DEST}" \
  -derivedDataPath "${DD}"

xcodebuild test-without-building \
  -scheme AEPFlags \
  -destination "${DEST}" \
  -only-testing:AEPFlagsTests \
  -parallel-testing-enabled NO \
  -derivedDataPath "${DD}"

xcodebuild test-without-building \
  -scheme AEPFlags \
  -destination "${DEST}" \
  -only-testing:FlagsEngineTests \
  ${SKIP_PERF_ARGS[@]+"${SKIP_PERF_ARGS[@]}"} \
  -parallel-testing-enabled NO \
  -derivedDataPath "${DD}"
