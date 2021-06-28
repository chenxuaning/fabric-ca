# Copyright IBM Corp All Rights Reserved.
# Copyright London Stock Exchange Group All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0

PROJECT_NAME = fabric-ca
BASE_VERSION = 1.5.0-gm
PREV_VERSION = 1.4.9
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

ifeq ($(ARCH),s390x)
PGVER=10
else
PGVER=10
endif

BASEIMAGE_RELEASE = 0.4.18
PKGNAME = github.com/hyperledger/$(PROJECT_NAME)

METADATA_VAR = Version=$(PROJECT_VERSION)

GO_SOURCE := $(shell find . -name '*.go')
GO_LDFLAGS = $(patsubst %,-X $(PKGNAME)/lib/metadata.%,$(METADATA_VAR))
export GO_LDFLAGS

IMAGES = $(PROJECT_NAME)

RELEASE_PLATFORMS = linux-amd64 darwin-amd64 linux-ppc64le linux-s390x windows-amd64
RELEASE_PKGS = fabric-ca-client fabric-ca-server

path-map.fabric-ca-client := cmd/fabric-ca-client
path-map.fabric-ca-server := cmd/fabric-ca-server

include docker-env.mk

docker: $(patsubst %,build/image/%/$(DUMMY), $(IMAGES))

fabric-ca-client: bin/fabric-ca-client
fabric-ca-server: bin/fabric-ca-server

bin/%: $(GO_SOURCE)
	@echo "Building ${@F} in bin directory ..."
	@mkdir -p bin && go build -o bin/${@F} -tags "pkcs11" -ldflags "$(GO_LDFLAGS)" $(PKGNAME)/$(path-map.${@F})
	@echo "Built bin/${@F}"

# We (re)build a package within a docker context but persist the $GOPATH/pkg
# directory so that subsequent builds are faster
build/docker/bin/%:
	@echo "Building $@"
	@mkdir -p $(@D) build/docker/$(@F)/pkg build/docker/cache
	@$(DRUN) \
		-v $(abspath build/docker/bin):/opt/gopath/bin \
		-v $(abspath build/docker/$(@F)/pkg):/opt/gopath/pkg \
		-v $(abspath build/docker/cache):/opt/gopath/cache \
		-e GOCACHE=/opt/gopath/cache \
		$(BASE_DOCKER_NS)/fabric-baseimage:$(BASE_DOCKER_TAG) \
		go install -ldflags "$(DOCKER_GO_LDFLAGS)" $(PKGNAME)/$(path-map.${@F})
	@touch $@

build/image/%/$(DUMMY): Makefile build/image/%/payload
	$(eval TARGET = ${patsubst build/image/%/$(DUMMY),%,${@}})
	$(eval DOCKER_NAME = $(DOCKER_NS)/$(TARGET))
	@echo "Building docker $(TARGET) image"
	@cat images/$(TARGET)/Dockerfile.in \
		| sed -e 's|_BASE_NS_|$(BASE_DOCKER_NS)|g' \
		| sed -e 's|_NS_|$(DOCKER_NS)|g' \
		| sed -e 's|_NEXUS_REPO_|$(NEXUS_URL)|g' \
		| sed -e 's|_BASE_TAG_|$(BASE_DOCKER_TAG)|g' \
		| sed -e 's|_FABRIC_TAG_|$(FABRIC_TAG)|g' \
		| sed -e 's|_STABLE_TAG_|$(STABLE_TAG)|g' \
		| sed -e 's|_TAG_|$(DOCKER_TAG)|g' \
		| sed -e 's|_PGVER_|$(PGVER)|g' \
		> $(@D)/Dockerfile
	$(DBUILD) -t $(DOCKER_NAME):$(DOCKER_TAG) --build-arg FABRIC_CA_DYNAMIC_LINK=$(FABRIC_CA_DYNAMIC_LINK) $(@D)
	@touch $@

build/image/fabric-ca/payload: \
	build/docker/bin/fabric-ca-client \
	build/docker/bin/fabric-ca-server \
	build/fabric-ca.tar.bz2
build/image/%/payload:
	@echo "Copying $^ to $@"
	mkdir -p $@
	cp $^ $@

build/fabric-ca.tar.bz2: $(shell git ls-files images/fabric-ca/payload)

build/%.tar.bz2:
	@echo "Building $@"
	@tar -jc -C images/$*/payload $(notdir $^) > $@

%-docker-clean:
	$(eval TARGET = ${patsubst %-docker-clean,%,${@}})
	-docker images -q $(DOCKER_NS)/$(TARGET):latest | xargs -I '{}' docker rmi -f '{}'
	-docker images -q $(NEXUS_URL)/*:$(STABLE_TAG) | xargs -I '{}' docker rmi -f '{}'
	-@rm -rf build/image/$(TARGET) ||:

docker-clean: $(patsubst %,%-docker-clean, $(IMAGES) $(PROJECT_NAME)-fvt)
	@rm -rf build/docker/bin/* ||:

docker-tag-push-gm: $(IMAGES:%=%-docker-tag-push-gm)

%-docker-tag-push-gm:
	$(eval TARGET = ${patsubst %-docker-tag-push-gm,%,${@}})
	docker tag $(DOCKER_NS)/$(TARGET):$(DOCKER_TAG) 172.16.10.134:8088/$(DOCKER_NS)/$(TARGET):$(DOCKER_TAG)
	docker push 172.16.10.134:8088/$(DOCKER_NS)/$(TARGET):$(DOCKER_TAG)

docker-push: $(patsubst %,%-docker-push, $(IMAGES))

native: fabric-ca-client fabric-ca-server

release: $(patsubst %,release/%, $(MARCH))
release-all: $(patsubst %,release/%, $(RELEASE_PLATFORMS))

release/darwin-amd64: GOOS=darwin
release/darwin-amd64: CC=/usr/bin/clang
release/darwin-amd64: $(patsubst %,release/darwin-amd64/bin/%, $(RELEASE_PKGS))

release/linux-amd64: GOOS=linux
release/linux-amd64: $(patsubst %,release/linux-amd64/bin/%, $(RELEASE_PKGS))

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
dist/darwin-amd64: release/darwin-amd64
	cd release/darwin-amd64 && tar -czvf hyperledger-fabric-ca-darwin-amd64-$(PROJECT_VERSION).tar.gz *
dist/linux-amd64: release/linux-amd64
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
