.PHONY: echo
echo:
	@echo "test"
# Relative build directory path.
BUILDDIR = build

# Absolute github repository name.
REPO             := github.com/Infoblox-CTO/csp.host-app.service

IMAGE_REGISTRY   ?= infobloxcto

APP_NAME         := athena.hostapp.
SVC_APP_NAME     := $(APP_NAME)svc
GOLANG_CONFIG    ?= .golangci-error.yml
BUILDTOOL_IMAGE  := infoblox/buildtool-alpine
BUILDER 	     := docker run --rm -v $(CURDIR):/go/src/$(REPO) $(OS) -w /go/src/$(REPO) $(BUILDTOOL_IMAGE)
BUILDER_NETHOST  := docker run --rm --net=host -v $(CURDIR):/go/src/$(REPO) $(OS) -w /go/src/$(REPO) $(BUILDTOOL_IMAGE)
REVIEWDOG_RUNNER := docker run --rm  --env-file ./reviewdog.env -v  $(CURDIR):/go/src/$(REPO)   -w /go/src/$(REPO) -i infobloxcto/linter:reviewdog bash -c "cat output.log | reviewdog -reporter=github-pr-review -efm='%E%f:%l:%c: %m' -efm='%E%f:%l: %m' -efm='%C%.%\#'"
LINTER_RUNNER    := docker run --rm -v  $(CURDIR):/go/src/$(REPO)   -w /go/src/$(REPO) -i golangci/golangci-lint:v1.19 golangci-lint run ./... --config=$(GOLANG_CONFIG) --out-format=line-number  > output.log

# Build flags for binaries with build info.
BUILDFLAGS = -ldflags='-X $(BUILDINFO_PKG).Revision=$(REVISION) -X $(BUILDINFO_PKG).Branch=$(BRANCH) -X $(BUILDINFO_PKG).Summary=$(SUMMARY) -X "$(BUILDINFO_PKG).Author=$(AUTHOR)" -X "$(BUILDINFO_PKG).Built=$(BUILD_DATE)" -X "$(BUILDINFO_PKG).Committed=$(COMMIT_DATE)" -X "$(BUILDINFO_PKG).GoVersion=$(GO_VERSION)"'

# Relative path to build directory
# files from '$(CURDIR)/cmd'.
BUILD_PATH = $(BUILDDIR)/bin
# Relative path to buildinfo package.
BUILDINFO_PKG = $(REPO)/internal/buildinfo

TAGGING_PROTO_PATH := github.com/Infoblox-CTO/atlas.tagging/pkg/operators
LICENSE_PROTO_PATH := github.com/Infoblox-CTO/athena.licensing/pkg/pb

ATLAS_TOOLKIT_REPO := github.com/infobloxopen/atlas-app-toolkit
TAGGING_REPO := github.com/Infoblox-CTO/atlas.tagging

# Utility docker image to generate Go files from .proto definition.
GENTOOL_IMAGE := infoblox/atlas-gentool:v16
GENTOOL_SWAGGER_PARAM = --swagger_out="atlas_patch=true,allow_delete_body=true:."

# Swagger Codegen image
SWAGGER_CODEGEN_IMAGE = swaggerapi/swagger-codegen-cli:2.4.1

# Configuration for building on host machine
GO_CACHE       := -pkgdir $(BUILD_PATH)/go-cache
GO_BUILD_FLAGS ?= $(GO_CACHE) -i -v
GO_TEST_FLAGS  ?= -v -cover
GO_PACKAGES    := $(shell $(BUILDER) go list ./... | grep -v "vendor/")

.PHONY: default
default: build

.PHONY: fmt
fmt:
	@go fmt $(GO_PACKAGES)

# Build info.
SOURCE ?= manual
SUMMARY := $(shell git describe --tags --dirty --always)
REVISION := $(shell git rev-parse HEAD)
BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
AUTHOR := $(shell git log -1 --pretty="format:%an - %ae")
BUILD_DATE := $(shell date -R)
COMMIT_DATE := $(shell git log -1 --format=%cd --date=rfc)
GO_VERSION := $(shell $(BUILDER) go version)

.PHONY: build
build: builddirs
	$(BUILDER) go build -o "$(BUILD_PATH)/hostapp" $(BUILDFLAGS) "$(REPO)/cmd/hostapp"

build-tools: builddirs
	$(BUILDER) go build -o "$(BUILD_PATH)/testgrpc" $(BUILDFLAGS) "$(REPO)/tools/testgrpc"

### BUILD HOSTAPP IMAGE ###

GIT_COMMIT     := $(shell git log -1 --pretty=format:%h)

ifeq ($(RELEASE_IMAGE_VERSION),)
  IMAGE_VERSION := $(shell date +%Y%m%d)-$(SOURCE)-$(GIT_COMMIT)
else
  IMAGE_VERSION := $(RELEASE_IMAGE_VERSION)
endif

IMAGE_SVC_NAME ?= $(IMAGE_REGISTRY)/$(SVC_APP_NAME):$(IMAGE_VERSION)

DB_VERSION        := $(shell ls migrations/*_*.up.sql | sort -r | head -n1 | cut -d/ -f2 | cut -d_ -f1)
SRV_VERSION       := $(shell git describe --tags)

SERVER_BINARY     := $(BUILD_PATH)/hostapp
SERVER_PATH       := $(REPO)/cmd/hostapp
SERVER_DOCKERFILE := docker/Dockerfile.hostapp

.PHONY: builddirs
builddirs:
	@mkdir -p "$(BUILD_PATH)"
	@mkdir -p "$(COVDIR_PATH)"

.PHONY: docker-prune
docker-prune:
	@docker image prune -f --filter label=stage=server-intermediate

.PHONY: clean
clean:
	@rm -rf "$(BUILD_PATH)"
	@rm -rf "$(COVDIR_PATH)"

### LOCAL DEVELOPMENT ###

dev-seed:
	@go run seeds/seeds.go

dev-up:
	@docker-compose up -d

dev-down:
	@docker-compose down

dev-http-client: protobuf dev-http-hostapp-client dev-http-registration-client

dev-http-hostapp-client: protobuf
	@docker run --rm --name swagger-codegen -d \
	-v $(CURDIR):/local \
	$(SWAGGER_CODEGEN_IMAGE) generate \
	-i /local/doc/v1/hostapp/hostapp.swagger.json \
    -l go \
    -o /local/pkg/client

dev-http-registration-client: protobuf
	@docker run --rm --name swagger-codegen-registration -d \
	-v $(CURDIR):/local \
	$(SWAGGER_CODEGEN_IMAGE) generate \
	-i /local/doc/v1/registration/registration.swagger.json \
    -l go \
    -o /local/pkg/regclient

dev-yaml:
	cd ./deploy/helm_v2; ./make-env.sh $(ENV)
	@echo -e "Use: \n less ./deploy/helm_v2/$(ENV)/$(ENV)_manifest.yaml\nto verify that manifest was generated correctly."

.PHONY: protobuf
protobuf: protobuf_hostapp protobuf_registration

.PHONY: protobuf_hostapp
protobuf_hostapp:
	@docker run --rm -v $(CURDIR):/go/src/$(REPO) \
	-v $(CURDIR)/vendor/$(TAGGING_PROTO_PATH):/go/src/$(TAGGING_PROTO_PATH) \
	-v $(CURDIR)/vendor/$(TAGGING_REPO)/filtering:/go/src/$(TAGGING_REPO)/filtering \
	-v $(CURDIR)/vendor/$(LICENSE_PROTO_PATH):/go/src/$(LICENSE_PROTO_PATH) \
	-v $(CURDIR)/vendor/$(ATLAS_TOOLKIT_REPO):/go/src/$(ATLAS_TOOLKIT_REPO) \
	$(GENTOOL_IMAGE) \
	--go_out=plugins=grpc:. \
	--grpc-gateway_out=logtostderr=true:. \
	--validate_out="lang=go:." \
	--atlas-validate_out="lang=go:." \
	$(GENTOOL_SWAGGER_PARAM) \
	-I$(TAGGING_PROTO_PATH)/operators.proto \
	-I$(LICENSE_PROTO_PATH)/service.proto \
	-I$(ATLAS_TOOLKIT_REPO)/query/collection_operators.proto \
	-Igithub.com/grpc-ecosystem/grpc-gateway \
	$(REPO)/pkg/pb/hostapp/hostapp.proto
	@mv -f $(CURDIR)/pkg/pb/hostapp/hostapp.swagger.json \
		$(CURDIR)/doc/v1/hostapp/

.PHONY: protobuf_registration
protobuf_registration:
	@docker run --rm -v $(CURDIR):/go/src/$(REPO) \
	-v $(CURDIR)/vendor/$(TAGGING_PROTO_PATH):/go/src/$(TAGGING_PROTO_PATH) \
	-v $(CURDIR)/vendor/$(TAGGING_REPO)/filtering:/go/src/$(TAGGING_REPO)/filtering \
	-v $(CURDIR)/vendor/$(LICENSE_PROTO_PATH):/go/src/$(LICENSE_PROTO_PATH) \
	-v $(CURDIR)/vendor/$(ATLAS_TOOLKIT_REPO):/go/src/$(ATLAS_TOOLKIT_REPO) \
	$(GENTOOL_IMAGE) \
	--go_out=plugins=grpc:. \
	--grpc-gateway_out=logtostderr=true:. \
	--validate_out="lang=go:." \
	--atlas-validate_out="lang=go:." \
	$(GENTOOL_SWAGGER_PARAM) \
	-I$(TAGGING_PROTO_PATH)/operators.proto \
	-I$(LICENSE_PROTO_PATH)/service.proto \
	-I$(ATLAS_TOOLKIT_REPO)/query/collection_operators.proto \
	-Igithub.com/grpc-ecosystem/grpc-gateway \
	$(REPO)/pkg/pb/registration/registration.proto
	@mv -f $(CURDIR)/pkg/pb/registration/registration.swagger.json \
		$(CURDIR)/doc/v1/registration/


### CI TESTS ###

ifdef GOOS
OS := -e GOOS=$(GOOS)
endif

COVDIR = $(BUILDDIR)/cov
COVDIR_PATH = $(CURDIR)/$(COVDIR)

.PHONY: test-unit
test-unit:
	$(BUILDER) bash -c 'set -o pipefail; \
	 go get github.com/axw/gocov/...  &&  \
	 go get github.com/AlekSi/gocov-xml && \
	 gocov test -v -tags=unit $(GO_PACKAGES) >$(COVDIR)/coverage.out && \
	 cat $(COVDIR)/coverage.out | gocov-xml > $(COVDIR)/coverage.xml'

.PHONY: test-integration
test-integration:
	$(BUILDER_NETHOST) bash -c 'go clean -testcache \
	&& go test -v ./... -tags=integration -p=1'
### LOCAL TESTS ###

dev-unit: fmt
	@echo "Starting unit tests..."
	@go test -v ./... -tags=unit

dev-integration: dev-up
	@echo "Starting local integration test..."
	@go clean -testcache
	@go test -v ./... -tags=integration -p=1

dev-test-all: dev-unit dev-integration


# PRAGMA linter-build lint-all
.PHONY: lint-all
lint-all:
ifeq ($(REVIEWDOG_GITHUB_API_TOKEN),)
	$(LINTER_RUNNER)
else
	$(LINTER_RUNNER)
	$(REVIEWDOG_RUNNER) 
endif
	

.PHONY: image push show-image-names show-image-version
image: build
	docker build --build-arg db_version=$(DB_VERSION) --build-arg api_version=v1 --build-arg srv_version=$(SRV_VERSION) -f $(SERVER_DOCKERFILE) -t $(IMAGE_SVC_NAME) .

push: image
	docker push $(IMAGE_SVC_NAME)

show-image-names:
	@echo $(SVC_APP_NAME)

show-image-version:
	@echo $(IMAGE_VERSION)

show-db-version:
	@echo $(DB_VERSION)
