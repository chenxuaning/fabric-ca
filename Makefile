# Copyright IBM Corp All Rights Reserved.
# Copyright London Stock Exchange Group All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0

PROJECT_NAME = fabric-ca
ALPINE_VER ?= 3.13
DEBIAN_VER ?= stretch
BASE_VERSION = 1.5.0
IS_RELEASE = false

ARCH=$(shell go env GOARCH)
MARCH=$(shell go env GOOS)-$(shell go env GOARCH)
STABLE_TAG ?= $(ARCH)-$(BASE_VERSION)-stable

ifneq ($(IS_RELEASE),true)
EXTRA_VERSION ?= $(shell git rev-parse --short HEAD)
PROJECT_VERSION=$(BASE_VERSION)-$(EXTRA_VERSION)
FABRIC_TAG ?= latest
else
PROJECT_VERSION=$(BASE_VERSION)
FABRIC_TAG ?= $(ARCH)-$(BASE_VERSION)
endif

PG_VER=11

PKGNAME = github.com/hyperledger/$(PROJECT_NAME)

METADATA_VAR = Version=$(PROJECT_VERSION)

GO_VER = 1.15.7
GO_SOURCE := $(shell find . -name '*.go')
GO_LDFLAGS = $(patsubst %,-X $(PKGNAME)/lib/metadata.%,$(METADATA_VAR))
export GO_LDFLAGS

IMAGES = $(PROJECT_NAME)
FVTIMAGE = $(PROJECT_NAME)-fvt

RELEASE_PLATFORMS = linux-amd64 darwin-amd64
RELEASE_PKGS = fabric-ca-client fabric-ca-server

TOOLS = build/tools

path-map.fabric-ca-client := cmd/fabric-ca-client
path-map.fabric-ca-server := cmd/fabric-ca-server

include docker-env.mk

docker: $(patsubst %,build/image/%/$(DUMMY), $(IMAGES))

fabric-ca-client: bin/fabric-ca-client
fabric-ca-server: bin/fabric-ca-server

vendor: .FORCE
	@go mod tidy
	@go mod vendor


bin/%: $(GO_SOURCE)
	@echo "Building ${@F} in bin directory ..."
	@mkdir -p bin && go build -o bin/${@F} -tags "pkcs11" -ldflags "$(GO_LDFLAGS)" $(PKGNAME)/$(path-map.${@F})
	@echo "Built bin/${@F}"

build/image/fabric-ca/$(DUMMY):
	@mkdir -p $(@D)
	$(eval TARGET = ${patsubst build/image/%/$(DUMMY),%,${@}})
	@echo "Docker:  building $(TARGET) image"
	$(DBUILD) -f images/$(TARGET)/Dockerfile \
		--build-arg GO_VER=${GO_VER} \
		--build-arg GO_TAGS=pkcs11 \
		--build-arg GO_LDFLAGS="${DOCKER_GO_LDFLAGS}" \
		--build-arg ALPINE_VER=${ALPINE_VER} \
		-t $(DOCKER_NS)/$(TARGET) .
	docker tag $(DOCKER_NS)/$(TARGET) $(DOCKER_NS)/$(TARGET):$(BASE_VERSION)
	docker tag $(DOCKER_NS)/$(TARGET) $(DOCKER_NS)/$(TARGET):$(DOCKER_TAG)
	@touch $@

%-docker-clean:
	$(eval TARGET = ${patsubst %-docker-clean,%,${@}})
	-docker images -q $(DOCKER_NS)/$(TARGET):latest | xargs -I '{}' docker rmi -f '{}'
	-@rm -rf build/image/$(TARGET) ||:

docker-clean: $(patsubst %,%-docker-clean, $(IMAGES) $(PROJECT_NAME)-fvt)
	@rm -rf build/docker/bin/* ||:

native: fabric-ca-client fabric-ca-server

release: $(patsubst %,release/%, $(MARCH))
release-all: $(patsubst %,release/%, $(RELEASE_PLATFORMS))


release/darwin-amd64: GOOS=darwin
release/darwin-amd64: CC=/usr/bin/clang
release/darwin-amd64: $(patsubst %,release/darwin-amd64/bin/%, $(RELEASE_PKGS))

release/linux-amd64: GOOS=linux
release/linux-amd64: $(patsubst %,release/linux-amd64/bin/%, $(RELEASE_PKGS))

release/%-amd64: GOARCH=amd64

release/linux-%: GOOS=linux

release/%/bin/fabric-ca-client: GO_TAGS+= caclient
release/%/bin/fabric-ca-client: $(GO_SOURCE)
	@echo "Building $@ for $(GOOS)-$(GOARCH)"
	mkdir -p $(@D)
	GOOS=$(GOOS) GOARCH=$(GOARCH) go build -o $(abspath $@) -tags "$(GO_TAGS)" -ldflags "$(GO_LDFLAGS)" $(PKGNAME)/$(path-map.$(@F))

release/%/bin/fabric-ca-server: $(GO_SOURCE)
	@echo "Building $@ for $(GOOS)-$(GOARCH)"
	mkdir -p $(@D)
	GOOS=$(GOOS) GOARCH=$(GOARCH) go build -o $(abspath $@) -tags "$(GO_TAGS)" -ldflags "$(GO_LDFLAGS)" $(PKGNAME)/$(path-map.$(@F))


.PHONY: dist
dist: dist-clean release
	cd release/$(MARCH) && tar -czvf hyperledger-fabric-ca-$(MARCH)-$(PROJECT_VERSION).tar.gz *
dist-all: dist-clean release-all $(patsubst %,dist/%, $(RELEASE_PLATFORMS))
dist/darwin-amd64:
	cd release/darwin-amd64 && tar -czvf hyperledger-fabric-ca-darwin-amd64-$(PROJECT_VERSION).tar.gz *
dist/linux-amd64:
	cd release/linux-amd64 && tar -czvf hyperledger-fabric-ca-linux-amd64-$(PROJECT_VERSION).tar.gz *

.PHONY: clean
clean: docker-clean release-clean
	-@rm -rf build bin ||:

.PHONY: clean-all
clean-all: clean dist-clean

%-release-clean:
	$(eval TARGET = ${patsubst %-release-clean,%,${@}})
	-@rm -rf release/$(TARGET)
release-clean: $(patsubst %,%-release-clean, $(RELEASE_PLATFORMS))

.PHONY: dist-clean
dist-clean:
	-@rm -rf release/darwin-amd64/hyperledger-fabric-ca-darwin-amd64-$(PROJECT_VERSION).tar.gz ||:
	-@rm -rf release/linux-amd64/hyperledger-fabric-ca-linux-amd64-$(PROJECT_VERSION).tar.gz ||:

.FORCE:
