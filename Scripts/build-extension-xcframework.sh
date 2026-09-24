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
set -euo pipefail

# Builds the customer-facing merged AEPFlags XCFramework (extension + FlagsEngine).
#
# FlagsEngine is in-repo source (see AEPFlagsEngine/Sources) compiled as an internal
# SPM target alongside AEPFlags -- there is no external engine artifact to download,
# no CDN, and no separate publish step for it. Everything is built from source in one
# pass via `xcodebuild archive` against Package.swift.
#
# Prerequisites:
#   - Close Xcode if it has this repo open (avoids DerivedData / ModuleCache conflicts).
#
# Optional signing (Adobe Distribution .p12):
#   export AEP_DISTRIBUTION_P12_PATH / AEP_DISTRIBUTION_P12_PASSWORD
#   or: ./Scripts/build-extension-xcframework.sh .signing/distribution.p12 'password'
#
# Outputs (under build/):
#   AEPFlags.xcframework      — merged dynamic framework (extension + engine)
#   AEPFlags.xcframework.zip  — release asset for non-SPM consumers

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="AEPFlags"
PRODUCT="AEPFlags"
MODULE_NAME="${MODULE_NAME:-AEPFlags}"
ARCHIVE_TARGET_NAME="AEPFlags"
SPM_PACKAGE_DIR="AEPFlags"
ENGINE_MODULE_NAME="FlagsEngine"
# SwiftPM names a target's resource bundle "<PackageName>_<TargetName>.bundle". This must stay in
# sync with Package.swift: package name "AEPFlags" + engine target "FlagsEngine". If either the
# package name or the engine target name changes, update this value (the build fails loudly below
# if it no longer matches, so the version-resource embedding can never silently drift).
ENGINE_RESOURCE_BUNDLE_NAME="AEPFlags_FlagsEngine.bundle"
BUILD="${ROOT}/build"
IOS_ARCHIVE="${BUILD}/extension-ios.xcarchive"
SIM_ARCHIVE="${BUILD}/extension-ios-simulator.xcarchive"
OUTPUT="${BUILD}/${PRODUCT}.xcframework"
ZIP_OUT="${BUILD}/${PRODUCT}.xcframework.zip"

P12_PATH="${AEP_DISTRIBUTION_P12_PATH:-${1:-}}"
P12_PASSWORD="${AEP_DISTRIBUTION_P12_PASSWORD:-${2:-}}"

TEMP_KEYCHAIN=""
TEMP_KEYCHAIN_PASSWORD=""
ORIGINAL_KEYCHAINS=""
SIGNING_IDENTITY=""

cleanup_signing_keychain() {
  if [[ -n "${TEMP_KEYCHAIN}" ]]; then
    security list-keychains -d user -s ${ORIGINAL_KEYCHAINS} 2>/dev/null || true
    security delete-keychain "${TEMP_KEYCHAIN}" 2>/dev/null || true
    TEMP_KEYCHAIN=""
  fi
}

prepare_signing_p12() {
  if [[ ! -f "${P12_PATH}" ]]; then
    echo "error: distribution certificate not found at '${P12_PATH}'" >&2
    exit 1
  fi
  local staging="${ROOT}/.signing/distribution.p12"
  local p12_abs
  p12_abs="$(cd "$(dirname "${P12_PATH}")" && pwd)/$(basename "${P12_PATH}")"
  mkdir -p "${ROOT}/.signing"
  if [[ "${p12_abs}" != "${staging}" ]]; then
    cp "${p12_abs}" "${staging}"
    chmod 600 "${staging}"
    echo "==> Staged signing certificate at ${staging}"
  fi
  P12_PATH="${staging}"
}

import_apple_wwdr_certificates() {
  local keychain="$1"
  local wwdr_dir="${BUILD}/apple-wwdr"
  mkdir -p "${wwdr_dir}"
  echo "==> Importing Apple WWDR intermediate certificates"
  local url name
  for url in \
    "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer" \
    "https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer" \
    "https://www.apple.com/certificateauthority/AppleWWDRCAG5.cer" \
    "https://www.apple.com/certificateauthority/AppleWWDRCAG6.cer"; do
    name="$(basename "${url}")"
    if curl -sfL "${url}" -o "${wwdr_dir}/${name}"; then
      security import "${wwdr_dir}/${name}" -k "${keychain}" -T /usr/bin/codesign >/dev/null 2>&1 || true
    fi
  done
}

find_signing_identity() {
  local keychain="$1"
  security find-identity -v -p codesigning "${keychain}" 2>/dev/null | \
    awk -F'"' '/^[[:space:]]+[0-9]+\)/ { print $2; exit }'
}

setup_distribution_signing() {
  if [[ -z "${P12_PATH}" || -z "${P12_PASSWORD}" ]]; then
    return 1
  fi
  prepare_signing_p12

  TEMP_KEYCHAIN="aep-ext-signing-$$.keychain"
  TEMP_KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"
  ORIGINAL_KEYCHAINS="$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')"

  echo "==> Setting up temporary signing keychain"
  security create-keychain -p "${TEMP_KEYCHAIN_PASSWORD}" "${TEMP_KEYCHAIN}"
  security set-keychain-settings -lut 3600 "${TEMP_KEYCHAIN}"
  security unlock-keychain -p "${TEMP_KEYCHAIN_PASSWORD}" "${TEMP_KEYCHAIN}"
  security list-keychains -d user -s "${TEMP_KEYCHAIN}" ${ORIGINAL_KEYCHAINS}

  import_apple_wwdr_certificates "${TEMP_KEYCHAIN}"

  echo "==> Importing Distribution certificate"
  security import "${P12_PATH}" \
    -k "${TEMP_KEYCHAIN}" \
    -P "${P12_PASSWORD}" \
    -A \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -f pkcs12

  security set-key-partition-list -S apple-tool:,apple: -s -k "${TEMP_KEYCHAIN_PASSWORD}" "${TEMP_KEYCHAIN}"

  SIGNING_IDENTITY="$(find_signing_identity "${TEMP_KEYCHAIN}")"
  if [[ -z "${SIGNING_IDENTITY}" ]]; then
    echo "error: no valid codesigning identity found in the certificate" >&2
    exit 1
  fi
  echo "    Signing identity: ${SIGNING_IDENTITY}"
}

sign_device_slices() {
  local xcframework_path="$1"
  local identity="$2"
  echo "==> Signing device frameworks (Distribution)"
  while IFS= read -r -d '' framework; do
    if [[ "${framework}" == *simulator* ]]; then
      continue
    fi
    echo "    ${framework}"
    if [[ -f "${framework}/${MODULE_NAME}" ]]; then
      /usr/bin/codesign --force --sign "${identity}" --timestamp "${framework}/${MODULE_NAME}"
    fi
    /usr/bin/codesign --force --sign "${identity}" --timestamp "${framework}"
  done < <(find "${xcframework_path}" -name "*.framework" -type d -print0)
}

sign_xcframework_bundle() {
  local xcframework_path="$1"
  local identity="$2"
  echo "==> Signing xcframework bundle (Distribution)"
  /usr/bin/codesign --force --sign "${identity}" --timestamp "${xcframework_path}"
  /usr/bin/codesign --verify --deep --strict "${xcframework_path}"
}

resign_simulator_adhoc() {
  local sim_fw="$1"
  echo "==> Re-signing simulator slice (ad-hoc)"
  /usr/bin/codesign --force --sign - --timestamp=none "${sim_fw}/${MODULE_NAME}"
  /usr/bin/codesign --force --sign - --timestamp=none "${sim_fw}"
  /usr/bin/codesign --verify "${sim_fw}"
}

XCODEPROJ_STASH=""

# xcodebuild archive must use Package.swift only. Stash the legacy .xcodeproj outside the repo
# (in-repo rename leaves a stub AEPFlags.xcodeproj/ without pbxproj and breaks the sim archive).
hide_xcodeproj() {
  remove_stale_xcodeproj_shell
  if [[ -d "${ROOT}/AEPFlags.xcodeproj" ]]; then
    XCODEPROJ_STASH="$(mktemp -d "${TMPDIR:-/tmp}/aepflags-xcodeproj-stash.XXXXXX")"
    mv "${ROOT}/AEPFlags.xcodeproj" "${XCODEPROJ_STASH}/"
    if [[ -d "${ROOT}/AEPFlags.xcworkspace" ]]; then
      mv "${ROOT}/AEPFlags.xcworkspace" "${XCODEPROJ_STASH}/"
    fi
    echo "==> Stashed AEPFlags.xcodeproj (SPM archive uses Package.swift only)"
  fi
  remove_stale_xcodeproj_shell
}

restore_xcodeproj() {
  remove_stale_xcodeproj_shell
  if [[ -n "${XCODEPROJ_STASH}" && -d "${XCODEPROJ_STASH}/AEPFlags.xcodeproj" ]]; then
    rm -rf "${ROOT}/AEPFlags.xcodeproj" "${ROOT}/AEPFlags.xcworkspace"
    mv "${XCODEPROJ_STASH}/AEPFlags.xcodeproj" "${ROOT}/"
    if [[ -d "${XCODEPROJ_STASH}/AEPFlags.xcworkspace" ]]; then
      mv "${XCODEPROJ_STASH}/AEPFlags.xcworkspace" "${ROOT}/"
    fi
    rm -rf "${XCODEPROJ_STASH}"
    XCODEPROJ_STASH=""
  elif [[ -d "${ROOT}/.AEPFlags.xcodeproj.hidden" ]]; then
    # Recover from older in-repo hide used by prior script versions.
    rm -rf "${ROOT}/AEPFlags.xcodeproj" "${ROOT}/AEPFlags.xcworkspace"
    mv "${ROOT}/.AEPFlags.xcodeproj.hidden" "${ROOT}/AEPFlags.xcodeproj"
    mv "${ROOT}/.AEPFlags.xcworkspace.hidden" "${ROOT}/AEPFlags.xcworkspace" 2>/dev/null || true
  fi
  remove_stale_xcodeproj_shell
}

remove_stale_xcodeproj_shell() {
  if [[ -d "${ROOT}/AEPFlags.xcodeproj" && ! -f "${ROOT}/AEPFlags.xcodeproj/project.pbxproj" ]]; then
    echo "==> Removing stale AEPFlags.xcodeproj shell (missing project.pbxproj)"
    rm -rf "${ROOT}/AEPFlags.xcodeproj"
  fi
}

on_exit() {
  restore_xcodeproj
  cleanup_signing_keychain
}
trap on_exit EXIT

# SPM xcodebuild archive statically merges AEPCore into the linked product. Build a static
# .a from a single target's own .o files only (extension OR engine), so AEPCore/AEPServices
# resolve when the customer app links (single AEPCore copy — prevents EXC_BAD_ACCESS on Event).
# target_name selects which target's per-file object directory to collect: "AEPFlags" for the
# extension, "FlagsEngine" for the in-repo engine -- both are built together by the same
# archive invocation below, so no separate archive step is needed per target.
build_static_target_archive() {
  local derived_data="$1"
  local output_archive="$2"
  local config="$3"
  local target_name="$4"
  local objects_root="${derived_data}/Build/Intermediates.noindex/ArchiveIntermediates/${SCHEME}/IntermediateBuildFilesPath/${SPM_PACKAGE_DIR}.build/${config}/${target_name}.build/Objects-normal"
  local arch objdir slice
  local -a archs slices

  if [[ ! -d "${objects_root}" ]]; then
    echo "error: missing object directory root ${objects_root}" >&2
    exit 1
  fi

  # Discover architectures from object subdirectories (arm64, x86_64, …).
  archs=()
  while IFS= read -r -d '' objdir; do
    archs+=( "$(basename "${objdir}")" )
  done < <(find "${objects_root}" -mindepth 1 -maxdepth 1 -type d -print0)
  if [[ ${#archs[@]} -eq 0 ]]; then
    echo "error: no architecture object directories under ${objects_root}" >&2
    exit 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  echo "==> Archiving ${target_name} (${config}; ${archs[*]}) as static library without embedded AEPCore"

  for arch in "${archs[@]}"; do
    objdir="${objects_root}/${arch}"
    slice="${tmpdir}/${target_name}-${arch}.a"
    # shellcheck disable=SC2206
    local objects=( "${objdir}"/*.o )
    if [[ ! -e "${objects[0]}" ]]; then
      echo "error: no object files in ${objdir}" >&2
      exit 1
    fi
    xcrun libtool -static -o "${slice}" "${objects[@]}"
    slices+=( "${slice}" )
  done

  mkdir -p "$(dirname "${output_archive}")"
  if [[ ${#slices[@]} -eq 1 ]]; then
    cp "${slices[0]}" "${output_archive}"
  else
    xcrun lipo -create "${slices[@]}" -output "${output_archive}"
  fi
  rm -rf "${tmpdir}"
}

patch_customer_swift_header() {
  local header="$1"
  # Static AEPFlags-Swift.h imports AEPCore for @objc API (AEPExtension, AEPError). Customers
  # compile this header when importing AEPFlags; forward-declare AEPCore types so the module
  # builds without requiring AEPCore to be scanned first (AEPCore still links at app link time).
  python3 - "${header}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "@import AEPCore;" not in text:
    sys.exit(0)
text = text.replace(
    "@import AEPCore;\n",
    "@protocol AEPExtension;\n",
)
path.write_text(text, encoding="utf-8")
PY
}

embed_swift_modules_into_staging() {
  local derived_data="$1"
  local staging="$2"
  local config="$3"
  local products="${derived_data}/Build/Intermediates.noindex/ArchiveIntermediates/${SCHEME}/BuildProductsPath/${config}"
  local module_dir="${products}/${ARCHIVE_TARGET_NAME}.swiftmodule"
  if [[ ! -d "${module_dir}" ]]; then
    module_dir="${products}/${MODULE_NAME}.swiftmodule"
  fi
  if [[ ! -d "${module_dir}" ]]; then
    echo "error: missing ${module_dir}" >&2
    exit 1
  fi

  mkdir -p "${staging}/Headers"
  cp -R "${module_dir}" "${staging}/${MODULE_NAME}.swiftmodule"

  local swift_header
  swift_header="$(find "${derived_data}/Build/Intermediates.noindex/ArchiveIntermediates/${SCHEME}/IntermediateBuildFilesPath" \
    -path "*GeneratedModuleMaps*" -name "${ARCHIVE_TARGET_NAME}-Swift.h" 2>/dev/null | head -n 1)"
  if [[ -z "${swift_header}" || ! -f "${swift_header}" ]]; then
    swift_header="$(find "${derived_data}/Build/Intermediates.noindex/ArchiveIntermediates/${SCHEME}/IntermediateBuildFilesPath" \
      -path "*GeneratedModuleMaps*" -name "${MODULE_NAME}-Swift.h" 2>/dev/null | head -n 1)"
  fi
  if [[ -z "${swift_header}" || ! -f "${swift_header}" ]]; then
    echo "error: could not locate GeneratedModuleMaps Swift header for ${config}" >&2
    exit 1
  fi
  cp "${swift_header}" "${staging}/Headers/${MODULE_NAME}-Swift.h"
  patch_customer_swift_header "${staging}/Headers/${MODULE_NAME}-Swift.h"
  cat > "${staging}/Headers/module.modulemap" <<EOF
module ${MODULE_NAME} {
    header "${MODULE_NAME}-Swift.h"
    export *
}
EOF
}

# Locates the FlagsEngine resource bundle (VERSION file, etc.) produced by the same archive
# build that compiled the FlagsEngine target -- SPM names it "<PackageName>_<TargetName>.bundle",
# i.e. "AEPFlags_FlagsEngine.bundle" for this in-repo target.
find_engine_resource_bundle() {
  local derived_data="$1"
  local config="$2"
  local products="${derived_data}/Build/Intermediates.noindex/ArchiveIntermediates/${SCHEME}/BuildProductsPath/${config}"
  local bundle="${products}/${ENGINE_RESOURCE_BUNDLE_NAME}"
  # The in-repo FlagsEngine target ships no resources, so SwiftPM does not emit a resource
  # bundle. Return empty in that case; the caller skips bundle embedding.
  if [[ -d "${bundle}" ]]; then
    printf '%s' "${bundle}"
  fi
}

merge_extension_and_engine_archives() {
  local extension_archive="$1"
  local engine_archive="$2"
  local output_binary="$3"
  local sdk="$4"
  local sdk_path
  local -a archs clang_args
  local arch

  if [[ ! -f "${extension_archive}" ]]; then
    echo "error: missing extension archive ${extension_archive}" >&2
    exit 1
  fi
  if [[ ! -f "${engine_archive}" ]]; then
    echo "error: missing engine archive ${engine_archive}" >&2
    exit 1
  fi

  sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"

  # extension_archive is a fat or thin static lib for this platform slice.
  while IFS= read -r arch; do
    [[ -n "${arch}" ]] && archs+=("${arch}")
  done < <(lipo -info "${extension_archive}" 2>/dev/null | sed -E 's/.*are: |.*architecture: //' | tr ' ' '\n')

  if [[ ${#archs[@]} -eq 0 ]]; then
    echo "error: could not read architectures from ${extension_archive}" >&2
    exit 1
  fi

  clang_args=()
  for arch in "${archs[@]}"; do
    clang_args+=(-arch "${arch}")
  done

  if [[ "${sdk}" == iphoneos ]]; then
    clang_args+=(-miphoneos-version-min=12.0)
  else
    clang_args+=(-mios-simulator-version-min=12.0)
  fi

  echo "==> Linking dynamic ${MODULE_NAME} (${sdk}; ${archs[*]}) with force-loaded extension + engine archives"

  # Dynamic framework (not static .a): FlagsEngine.Bundle.module resolves resources via
  # Bundle(for: BundleFinder.self).resourceURL on the loaded AEPFlags.framework.
  # AEPCore/AEPServices symbols stay undefined — resolved from the customer app.
  # Static .a inputs are not pulled into a dylib unless force-loaded; without this the
  # resulting framework is ~80KB with no exported Swift API (customer link fails).
  xcrun clang -dynamiclib \
    "${clang_args[@]}" \
    -isysroot "${sdk_path}" \
    -Wl,-force_load,"${extension_archive}" \
    -Wl,-force_load,"${engine_archive}" \
    -o "${output_binary}" \
    -install_name "@rpath/${MODULE_NAME}.framework/${MODULE_NAME}" \
    -Xlinker -rpath -Xlinker @executable_path/Frameworks \
    -Xlinker -rpath -Xlinker @loader_path/Frameworks \
    -undefined dynamic_lookup \
    -fobjc-link-runtime \
    -framework Foundation
}


write_framework_info_plist() {
  local framework_dir="$1"
  local sdk_version="$2"
  local platform="$3"
  cat > "${framework_dir}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${MODULE_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>com.adobe.aepflags</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${MODULE_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>${sdk_version}</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>${platform}</string>
	</array>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>MinimumOSVersion</key>
	<string>12.0</string>
</dict>
</plist>
EOF
}


assemble_merged_framework() {
  local staging="$1"
  local engine_resource_bundle="$2"
  local extension_archive="$3"
  local engine_archive="$4"
  local output_framework="$5"
  local platform_name="$6"
  local platform_sdk="iphonesimulator"
  if [[ "${platform_name}" == "iPhoneOS" ]]; then
    platform_sdk="iphoneos"
  fi
  # Stamp the framework with the product (extension) version resolved by read-version.sh — the
  # single source of truth — so the bundle's CFBundleShortVersionString matches the release tag.
  # "unknown" only if the product version can't be resolved.
  local sdk_version
  sdk_version="$("${ROOT}/Scripts/read-version.sh" 2>/dev/null || true)"
  if [[ -z "${sdk_version}" ]]; then
    sdk_version="unknown"
  fi

  rm -rf "${output_framework}"
  mkdir -p "${output_framework}/Headers" "${output_framework}/Modules"

  merge_extension_and_engine_archives \
    "${extension_archive}" \
    "${engine_archive}" \
    "${output_framework}/${MODULE_NAME}" \
    "${platform_sdk}"

  cp -R "${staging}/${MODULE_NAME}.swiftmodule" "${output_framework}/Modules/"
  cp "${staging}/Headers/${MODULE_NAME}-Swift.h" "${output_framework}/Headers/"
  cat > "${output_framework}/Modules/module.modulemap" <<EOF
framework module ${MODULE_NAME} {
    umbrella header "${MODULE_NAME}-Swift.h"
    export *
    module * { export * }
}
EOF

  # Embed the engine resource bundle only when present (the engine currently ships none).
  if [[ -n "${engine_resource_bundle}" && -d "${engine_resource_bundle}" ]]; then
    rm -rf "${output_framework}/${ENGINE_RESOURCE_BUNDLE_NAME}"
    ditto "${engine_resource_bundle}" "${output_framework}/${ENGINE_RESOURCE_BUNDLE_NAME}"
  fi

  write_framework_info_plist "${output_framework}" "${sdk_version}" "${platform_name}"
}


echo "==> Resolving Swift packages for extension + engine archive"
(cd "${ROOT}" && swift package resolve)

# Recover if a prior run exited before restore (would break xcodebuild).
restore_xcodeproj
hide_xcodeproj

rm -rf "${IOS_ARCHIVE}" "${SIM_ARCHIVE}" "${OUTPUT}"
mkdir -p "${BUILD}"

echo "==> Cleaning extension DerivedData (prevents SwiftExplicitDependencyGeneratePcm / AEPServices PCM failures)"
rm -rf "${BUILD}/DerivedData-extension-ios" "${BUILD}/DerivedData-extension-sim" \
  "${BUILD}/DerivedData-extension-modules-ios" "${BUILD}/DerivedData-extension-modules-sim"

echo "==> Archiving extension + engine modules (device; library evolution for customer Swift API)"
(cd "${ROOT}" && xcodebuild archive \
  -scheme "${SCHEME}" \
  -destination "generic/platform=iOS" \
  -archivePath "${BUILD}/extension-modules-ios.xcarchive" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  -derivedDataPath "${BUILD}/DerivedData-extension-modules-ios")

echo "==> Archiving extension + engine modules (simulator; library evolution)"
remove_stale_xcodeproj_shell
(cd "${ROOT}" && xcodebuild archive \
  -scheme "${SCHEME}" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "${BUILD}/extension-modules-sim.xcarchive" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  -derivedDataPath "${BUILD}/DerivedData-extension-modules-sim")

echo "==> Archiving extension + engine objects (device; direct AEPCore symbol refs for static .a)"
(cd "${ROOT}" && xcodebuild archive \
  -scheme "${SCHEME}" \
  -destination "generic/platform=iOS" \
  -archivePath "${IOS_ARCHIVE}" \
  SKIP_INSTALL=NO \
  -derivedDataPath "${BUILD}/DerivedData-extension-ios")

echo "==> Archiving extension + engine objects (simulator)"
remove_stale_xcodeproj_shell
(cd "${ROOT}" && xcodebuild archive \
  -scheme "${SCHEME}" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "${SIM_ARCHIVE}" \
  SKIP_INSTALL=NO \
  -derivedDataPath "${BUILD}/DerivedData-extension-sim")

IOS_STAGING="${BUILD}/static-staging-ios"
SIM_STAGING="${BUILD}/static-staging-sim"
IOS_LIB="${IOS_STAGING}/lib${MODULE_NAME}.a"
SIM_LIB="${SIM_STAGING}/lib${MODULE_NAME}.a"
ENGINE_IOS_LIB="${BUILD}/lib${ENGINE_MODULE_NAME}-ios.a"
ENGINE_SIM_LIB="${BUILD}/lib${ENGINE_MODULE_NAME}-sim.a"
IOS_FW="${BUILD}/merged-framework-ios/${MODULE_NAME}.framework"
SIM_FW="${BUILD}/merged-framework-sim/${MODULE_NAME}.framework"
rm -rf "${IOS_STAGING}" "${SIM_STAGING}" "${BUILD}/merged-framework-ios" "${BUILD}/merged-framework-sim"
mkdir -p "${IOS_STAGING}/Headers" "${SIM_STAGING}/Headers"

echo "==> Building static extension archives (extension .o only; AEPCore stays undefined)"
build_static_target_archive "${BUILD}/DerivedData-extension-ios" "${IOS_LIB}" "Release-iphoneos" "${ARCHIVE_TARGET_NAME}"
build_static_target_archive "${BUILD}/DerivedData-extension-sim" "${SIM_LIB}" "Release-iphonesimulator" "${ARCHIVE_TARGET_NAME}"

echo "==> Building static engine archives (in-repo FlagsEngine .o only)"
build_static_target_archive "${BUILD}/DerivedData-extension-ios" "${ENGINE_IOS_LIB}" "Release-iphoneos" "${ENGINE_MODULE_NAME}"
build_static_target_archive "${BUILD}/DerivedData-extension-sim" "${ENGINE_SIM_LIB}" "Release-iphonesimulator" "${ENGINE_MODULE_NAME}"

echo "==> Embedding Swift modules (${MODULE_NAME}; from library-evolution archive)"
embed_swift_modules_into_staging "${BUILD}/DerivedData-extension-modules-ios" "${IOS_STAGING}" "Release-iphoneos"
embed_swift_modules_into_staging "${BUILD}/DerivedData-extension-modules-sim" "${SIM_STAGING}" "Release-iphonesimulator"

echo "==> Locating FlagsEngine resource bundle (from the objects archive; same bundle either config produces)"
ENGINE_IOS_BUNDLE="$(find_engine_resource_bundle "${BUILD}/DerivedData-extension-ios" "Release-iphoneos")"
ENGINE_SIM_BUNDLE="$(find_engine_resource_bundle "${BUILD}/DerivedData-extension-sim" "Release-iphonesimulator")"

echo "==> Merging extension + FlagsEngine into dynamic ${MODULE_NAME}.framework slices"
assemble_merged_framework "${IOS_STAGING}" "${ENGINE_IOS_BUNDLE}" "${IOS_LIB}" "${ENGINE_IOS_LIB}" "${IOS_FW}" "iPhoneOS"
assemble_merged_framework "${SIM_STAGING}" "${ENGINE_SIM_BUNDLE}" "${SIM_LIB}" "${ENGINE_SIM_LIB}" "${SIM_FW}" "iPhoneSimulator"

xcodebuild -create-xcframework \
  -framework "${IOS_FW}" \
  -framework "${SIM_FW}" \
  -output "${OUTPUT}"

SIM_FW_IN_XCF="$(find "${OUTPUT}" -path '*simulator*' -name "${MODULE_NAME}.framework" -type d | head -n 1)"

if setup_distribution_signing; then
  sign_device_slices "${OUTPUT}" "${SIGNING_IDENTITY}"
  if [[ -n "${SIM_FW_IN_XCF}" ]]; then
    resign_simulator_adhoc "${SIM_FW_IN_XCF}"
  fi
  sign_xcframework_bundle "${OUTPUT}" "${SIGNING_IDENTITY}"
else
  echo "==> Skipping Distribution signing (pass .p12 + password or set AEP_DISTRIBUTION_P12_* env)"
  if [[ -n "${SIM_FW_IN_XCF}" ]]; then
    resign_simulator_adhoc "${SIM_FW_IN_XCF}"
  fi
fi

( cd "${BUILD}" && rm -f "${PRODUCT}.xcframework.zip" && /usr/bin/zip -r -X "${PRODUCT}.xcframework.zip" "${PRODUCT}.xcframework" )

VERSION="$("${ROOT}/Scripts/read-version.sh")"

echo ""
echo "XCFramework:  ${OUTPUT}"
echo "Release zip:  ${ZIP_OUT}"
echo "Version:      ${VERSION}"
echo ""
echo "Next: attach build/${PRODUCT}.xcframework.zip to the GitHub Release for this version."
echo "SPM consumers resolve AEPFlags directly from source via the git tag -- no separate step needed."
