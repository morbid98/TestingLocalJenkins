BUILDDIR = build
BUILD_PATH = $(BUILDDIR)/bin
REPO       := github.com/Infoblox-CTO/csp.host-app.service
BUILDER .  := docker run --rm -v $(CURDIR):/go/src/$(REPO) $(OS) -w /go/src/$(REPO) $(BUILDTOOL_IMAGE)
BUILDTOOL_IMAGE  := infoblox/buildtool-alpine


.PHONY: echo
echo:
	@echo "test"
	
.PHONY: build
build: builddirs
	$(BUILDER) go build -o "$(BUILD_PATH)/hostapp" $(BUILDFLAGS) "$(REPO)/cmd/hostapp"
