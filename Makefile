export EXTENSION_NAME = AEPFlags
CURRENT_DIRECTORY := ${CURDIR}

IOS_SIM_SDK := $(shell xcrun --sdk iphonesimulator --show-sdk-path)
IOS_SIM_ARCH := $(shell uname -m)
IOS_SIM_TRIPLE := $(IOS_SIM_ARCH)-apple-ios17.0-simulator
SPM_BUILD_FLAGS := --sdk $(IOS_SIM_SDK) --triple $(IOS_SIM_TRIPLE)
IOS_SIM_DEST := $(shell ./Scripts/resolve_ios_sim_dest.sh)

build-extension-xcf:
	./Scripts/build-extension-xcframework.sh

check-version:
	sh ./Scripts/version.sh $(VERSION)

update-version:
	sh ./Scripts/update-version.sh -v $(VERSION) $(if $(DEPENDENCIES),-d "$(DEPENDENCIES)",)

build:
	swift package resolve
	swift build $(SPM_BUILD_FLAGS)

test:
	./Scripts/run_spm_tests.sh $(if $(filter command line environment,$(origin DEST)),"$(DEST)",)

test-build:
	swift package resolve
	swift build $(SPM_BUILD_FLAGS) --build-tests

resolve:
	swift package resolve

# Lint the SDK sources (see .swiftlint.yml). Requires SwiftLint on PATH (brew install swiftlint).
lint:
	swiftlint lint --config .swiftlint.yml

# Auto-fix the mechanically-correctable lint violations in place.
lint-autocorrect:
	swiftlint --fix --config .swiftlint.yml

format: lint-autocorrect

# Verify a downstream Swift Package Manager consumer can resolve + compile against AEPFlags.
test-SPM-integration:
	./Scripts/test-spm-integration.sh

customer-demo:
	open TestApps/FlagsDemoApp/FlagsDemoApp.xcodeproj

objc-demo:
	open TestApps/FlagsDemoAppObjC/FlagsDemoAppObjC.xcodeproj

customer-demo-build:
	xcodebuild -resolvePackageDependencies -project TestApps/FlagsDemoApp/FlagsDemoApp.xcodeproj -scheme FlagsDemoApp
	xcodebuild build -project TestApps/FlagsDemoApp/FlagsDemoApp.xcodeproj -scheme FlagsDemoApp \
	  -destination '$(if $(filter command line environment,$(origin DEST)),$(DEST),$(IOS_SIM_DEST))' \
	  -derivedDataPath .build/customer-demo-dd

objc-demo-build:
	xcodebuild -resolvePackageDependencies -project TestApps/FlagsDemoAppObjC/FlagsDemoAppObjC.xcodeproj -scheme FlagsDemoAppObjC
	xcodebuild build -project TestApps/FlagsDemoAppObjC/FlagsDemoAppObjC.xcodeproj -scheme FlagsDemoAppObjC \
	  -destination '$(if $(filter command line environment,$(origin DEST)),$(DEST),$(IOS_SIM_DEST))' \
	  -derivedDataPath .build/objc-demo-dd

.PHONY: build-extension-xcf check-version update-version build test test-build resolve \
	lint lint-autocorrect format test-SPM-integration \
	customer-demo objc-demo customer-demo-build objc-demo-build
