SHELL := /bin/bash

BUILD_INFO := Sources/UnfairDaemon/BuildInfo.swift

.PHONY: build release install uninstall generate-build-info

build:
	@set -euo pipefail; \
	original="$$(mktemp)"; \
	cp "$(BUILD_INFO)" "$$original"; \
	restore() { cp "$$original" "$(BUILD_INFO)"; rm -f "$$original"; }; \
	trap restore EXIT; \
	$(MAKE) generate-build-info; \
	swift build

release:
	@set -euo pipefail; \
	original="$$(mktemp)"; \
	cp "$(BUILD_INFO)" "$$original"; \
	restore() { cp "$$original" "$(BUILD_INFO)"; rm -f "$$original"; }; \
	trap restore EXIT; \
	$(MAKE) generate-build-info; \
	swift build -c release

install: release
	bash deploy/install-launchdaemon.sh

uninstall:
	bash deploy/uninstall-launchdaemon.sh

generate-build-info:
	@commit="$$(git rev-parse --short=12 HEAD 2>/dev/null || awk -F'"' '/static let commit/ { print $$2; exit }' "$(BUILD_INFO)" 2>/dev/null || echo unknown)"; \
	if [[ -z "$$commit" ]]; then commit="unknown"; fi; \
	timestamp="$$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
	printf 'enum BuildInfo {\n    static let commit = "%s"\n    static let timestamp = "%s"\n}\n' "$$commit" "$$timestamp" > "$(BUILD_INFO)"
