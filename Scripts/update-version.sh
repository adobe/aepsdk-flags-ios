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
# Bump the product version (and, optionally, AEP dependency lower bounds). Driven by the
# Update Version GitHub Actions workflow -- humans do not edit version files by hand.
#
# Product version is single-sourced in AEPFlags/Sources/FlagConstants.swift `extensionVersion`.
# The whole quoted value is replaced, so pre-release suffixes (e.g. 5.1.0-beta) are handled.
#
# Usage:
#   sh ./Scripts/update-version.sh -v <version> [-d "AEPCore x.y.z, AEPEdge a.b.c, AEPEdgeIdentity d.e.f"]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONSTANTS="${ROOT}/AEPFlags/Sources/FlagConstants.swift"
PACKAGE_SWIFT="${ROOT}/Package.swift"
DEP_SEMVER='[0-9]+\.[0-9]+\.[0-9]+'

NEW_VERSION=""
DEPENDENCIES=""
while getopts ":v:d:" opt; do
  case "${opt}" in
    v) NEW_VERSION="${OPTARG}" ;;
    d) DEPENDENCIES="${OPTARG}" ;;
    *) echo "[error] usage: sh ./Scripts/update-version.sh -v <version> [-d \"Dep x.y.z, ...\"]" >&2; exit 1 ;;
  esac
done

if [[ -z "${NEW_VERSION}" ]]; then
  echo "[error] -v <version> is required" >&2
  exit 1
fi

# 1) Product version constant -- replace the entire quoted value (suffix-safe).
echo "==> Setting FlagConstants.extensionVersion to ${NEW_VERSION}"
sed -i '' -E "s/(static let extensionVersion[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1${NEW_VERSION}\2/" "${CONSTANTS}"

# 2) Optional AEP dependency lower bounds in Package.swift (.upToNextMajor(from: "x.y.z")).
map_repo_url() {
  case "$1" in
    AEPCore|AEPServices) echo "aepsdk-core-ios" ;;
    AEPEdge) echo "aepsdk-edge-ios" ;;
    AEPEdgeIdentity) echo "aepsdk-edgeidentity-ios" ;;
    *) echo "" ;;
  esac
}

if [[ -n "${DEPENDENCIES}" ]]; then
  IFS=',' read -ra PAIRS <<< "${DEPENDENCIES}"
  for pair in "${PAIRS[@]}"; do
    dep_name="$(echo "${pair}" | awk '{$1=$1};1' | cut -d' ' -f1)"
    dep_ver="$(echo "${pair}" | awk '{$1=$1};1' | cut -d' ' -f2)"
    [[ -z "${dep_name}" || -z "${dep_ver}" ]] && continue
    repo="$(map_repo_url "${dep_name}")"
    if [[ -z "${repo}" ]]; then
      echo "==> Skipping unknown dependency '${dep_name}'"
      continue
    fi
    if ! [[ "${dep_ver}" =~ ^${DEP_SEMVER}$ ]]; then
      echo "[error] dependency '${dep_name}' version '${dep_ver}' is not X.Y.Z" >&2
      exit 1
    fi
    echo "==> Setting ${dep_name} (${repo}) lower bound to ${dep_ver}"
    repo_re="$(echo "${repo}" | sed 's/[.]/\\./g')"
    sed -i '' -E "/${repo_re}\.git/ s/(\.upToNextMajor\(from: \")${DEP_SEMVER}(\")/\1${dep_ver}\2/" "${PACKAGE_SWIFT}"
  done
fi

echo "==> Done. Updated version to ${NEW_VERSION}."
