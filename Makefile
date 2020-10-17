# Disable all the default make stuff
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

ARTIFACT_DIR ?= artifacts

# Add more binaries to the BINARIES variable. These should exist as cmd/*/main.go
BINARIES ?= spoon-oci

# The platform specific binaries to build. Add more here if you need to support windows or other architectures.
ARTIFACT_BINARIES := $(addprefix $(ARTIFACT_DIR)/,$(BINARIES:=.linux.amd64) $(BINARIES:=.darwin.amd64) $(BINARIES:=.windows.amd64))

GO_BINARY = $(if $(USE_DOCKER),docker run --rm -t -e GOOS=$(GOOS) -e GOARCH=$(GOARCH) -e GOFLAGS=$(GOFLAGS) -v $(PWD):/__ -w /__ golang:1.15 go,GOOS=$(GOOS) GOARCH=$(GOARCH) GOFLAGS=$(GOFLAGS) go)
GO_FILES = $(shell find $(subst /__/,$(shell pwd)/,$(shell $(GO_BINARY) list -f '{{ .Dir }}' ./...) -type f -name '*.go'))
GO_DEPENDENCIES = $(GO_FILES) go.sum go.mod

# Verbose logging in tests and build
V_FLAG := $(if $(V),-v,)

# Logging function used for some consistency - the if/else is used to turn off colors when no TTY exists
ifeq "$(shell [ -t 0 ] && echo 1)" "1"
LOG = @echo "\033[38;5;13m$(shell date):\033[0m"
else
LOG = @echo $(shell date):
endif

# Shasums command
SHASUMS := $(if $(shell uname | grep Darwin),shasum -a 256,sha256sum)

## Display a list of the documented make targets
.PHONY: help
help:
	@echo Documented Make targets:
	@perl -e 'undef $$/; while (<>) { while ($$_ =~ /## (.*?)(?:\n# .*)*\n.PHONY:\s+(\S+).*/mg) { printf "\033[36m%-30s\033[0m %s\n", $$2, $$1 } }' $(MAKEFILE_LIST) | sort

# ------------------------------------------------------------------------------
# NON-PHONY TARGETS
# ------------------------------------------------------------------------------

.PHONY: .FORCE
.FORCE:

# Need a fake rule for this, but we'll allow go build to generate it when needed
go.sum:
	true

# Create the artifactory directory
$(ARTIFACT_DIR):
	$(LOG) Creating artifact dir $@..
	@mkdir -p $@

# Build the development binary
$(BINARIES): $(GO_DEPENDENCIES)
	$(LOG) Building $@...
	@$(GO_BINARY) build -o $@ $(V_FLAG) .

# Write the current git describe state
$(ARTIFACT_DIR)/describe: .FORCE | $(ARTIFACT_DIR)
	@git describe --always --tags --long --dirty --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null > $@.new
	@cmp $@.new $@ 2>/dev/null || mv -f $@.new $@
	@rm -f $@.new

# Write the semantic version string file
$(ARTIFACT_DIR)/semver: describe = $(shell cat $(ARTIFACT_DIR)/describe)
$(ARTIFACT_DIR)/semver: $(ARTIFACT_DIR)/describe
	$(LOG) Writing new semver file $@..
	@echo $(if $(describe:v%=),0.0.1-0-)$(describe) | sed -e 's/^v//; s/-/\#/; s/-/./g; s/\#/-/' > $@

# Build the release binaries
$(ARTIFACT_BINARIES): t = $(subst ., ,$(notdir $@))
$(ARTIFACT_BINARIES): GOOS = $(word 2,$(t))
$(ARTIFACT_BINARIES): GOARCH = $(word 3,$(t))
$(ARTIFACT_BINARIES): $(GO_DEPENDENCIES) $(ARTIFACT_DIR)/semver
	$(LOG) Building $@ with version $(shell cat $(ARTIFACT_DIR)/semver)..
	@$(GO_BINARY) build \
		-o $@ \
		-ldflags '-X main.version=$(shell cat $(ARTIFACT_DIR)/semver)+$(USER) -X "main.buildDate=$(shell date)"' \
		$(V_FLAG) \
		.

# Write a shasums file for the artifact binaries
$(ARTIFACT_DIR)/SHA256SUMS: $(ARTIFACT_BINARIES)
	$(LOG) Calculating shasums for binaries..
	@cd $(dir $@) && $(SHASUMS) $(notdir $(ARTIFACT_BINARIES)) > $(notdir $@)

# Write coverage file
$(ARTIFACT_DIR)/coverage.out: $(GO_DEPENDENCIES) | $(ARTIFACT_DIR)
	$(LOG) Running unittests with coverage..
	@$(GO_BINARY) test $(V_FLAG) -cover -covermode=count -coverprofile=$@ ./...
	$(LOG) Running vet checks..
	@$(GO_BINARY) vet $(V_FLAG) ./...

# ------------------------------------------------------------------------------
# PHONY TARGETS
# ------------------------------------------------------------------------------

## Print the version information
.PHONY: version
version: $(ARTIFACT_DIR)/semver
	@cat $<

## Build development binary on local system
.PHONY: dev
ifeq "$(BINARIES)" ""
dev:
	$(LOG) BINARIES is not defined in Makefile, nothing to do.
else
dev: $(BINARIES)
	$(LOG) Development binaries available at: $^
endif

## Build release binaries
.PHONY: build
ifeq "$(BINARIES)" ""
build:
	$(LOG) BINARIES is not defined in Makefile, nothing to do.
else
build: $(ARTIFACT_BINARIES) $(ARTIFACT_DIR)/SHA256SUMS
	$(LOG) Artifact binaries available at: $^
endif

## Run unittests
.PHONY: test
test: $(ARTIFACT_DIR)/coverage.out

## Run linting
.PHONY: lint
lint:
	golangci-lint run

## Print function coverage
.PHONY: coverage
coverage: $(ARTIFACT_DIR)/coverage.out
	$(LOG) Printing function Coverage..
	@$(GO_BINARY) tool cover -func $<

## Open coverage in browser
.PHONY: coverage-html
coverage-html: $(ARTIFACT_DIR)/coverage.out
	$(LOG) Printing function Coverage..
	@$(GO_BINARY) tool cover -html $<

## Clean old files and artifacts
.PHONY: clean
clean:
	$(LOG) Cleaning old files..
	@rm -rfv $(ARTIFACT_DIR) $(BINARIES)
