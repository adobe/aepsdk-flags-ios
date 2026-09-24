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
# Resolves the Flags iOS extension version string for release scripts and CI.
# Priority: FLAGS_EXTENSION_VERSION env → git tag (v*) → FlagConstants.extensionVersion.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${FLAGS_EXTENSION_VERSION:-}" ]]; then
  printf '%s' "${FLAGS_EXTENSION_VERSION}"
  exit 0
fi

if TAG="$(git -C "${ROOT}" describe --tags --match 'v*' --abbrev=0 2>/dev/null)"; then
  printf '%s' "${TAG#v}"
  exit 0
fi

CONSTANTS="${ROOT}/AEPFlags/Sources/FlagConstants.swift"
if [[ -f "${CONSTANTS}" ]]; then
  VERSION="$(sed -n 's/.*extensionVersion = "\([^"]*\)".*/\1/p' "${CONSTANTS}" | head -n 1)"
  if [[ -n "${VERSION}" ]]; then
    printf '%s' "${VERSION}"
    exit 0
  fi
fi

echo "error: could not resolve extension version (set FLAGS_EXTENSION_VERSION or tag the repo)" >&2
exit 1
