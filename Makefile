PROJECT := papaSteps.xcodeproj
SCHEME := papaSteps
DERIVED_DATA ?= /private/tmp/papaStepsDerivedData
DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=latest

.PHONY: build release-build test ui-test ci

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

release-build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -only-testing:papaStepsTests

ui-test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -only-testing:papaStepsUITests

ci: build release-build test ui-test
