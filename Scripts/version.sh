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
# Validate that the source product version matches an expected version (usually the release tag).
# The product version is single-sourced in AEPFlags/Sources/FlagConstants.swift `extensionVersion`.
# There is no podspec or project.pbxproj to cross-check (SPM + xcframework distribution only).
# Usage: sh ./Scripts/version.sh <expected-version>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONSTANTS="${ROOT}/AEPFlags/Sources/FlagConstants.swift"

EXPECTED="${1:-}"
if [[ -z "${EXPECTED}" ]]; then
  echo "[error] usage: sh ./Scripts/version.sh <expected-version>" >&2
  exit 1
fi

SOURCE_VERSION="$(sed -n 's/.*extensionVersion[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${CONSTANTS}" | head -n 1)"
if [[ -z "${SOURCE_VERSION}" ]]; then
  echo "[error] could not read extensionVersion from ${CONSTANTS}" >&2
  exit 1
fi

if [[ "${EXPECTED}" == "${SOURCE_VERSION}" ]]; then
  echo "Pass! Version ${EXPECTED} matches FlagConstants.extensionVersion."
  exit 0
fi

echo "[error] Version mismatch: expected '${EXPECTED}' but FlagConstants.extensionVersion is '${SOURCE_VERSION}'." >&2
echo "        Run the Update Version workflow (or Scripts/update-version.sh) to bump the source first." >&2
exit 1
