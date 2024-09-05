UPLOAD_TARGETS := $(addprefix upload-,$(shell ls policy/))
BUILD_TARGETS := $(addprefix build-,$(shell ls policy/))
SIGN_TARGETS := $(addprefix sign-,$(shell ls policy/))
.dapper:
	@echo Downloading dapper
	@curl -sL https://releases.rancher.com/dapper/latest/dapper-$$(uname -s)-$$(uname -m) > .dapper.tmp
	@@chmod +x .dapper.tmp
	@./.dapper.tmp -v
	@mv .dapper.tmp .dapper

$(BUILD_TARGETS): .dapper
	./.dapper -f Dockerfile.$(@:build-%=%).dapper ./policy/$(@:build-%=%)/scripts/build

$(SIGN_TARGETS): .dapper
	./.dapper -f Dockerfile.centos7.dapper ./policy/$(@:sign-%=%)/scripts/sign

$(UPLOAD_TARGETS): .dapper
	./.dapper -f Dockerfile.centos7.dapper ./policy/$(@:upload-%=%)/scripts/upload-repo

clean:
	rm -rf dist/ Dockerfile.*.dapper[0-9]*

.PHONY: $(UPLOAD_TARGETS) $(BUILD_TARGETS) $(SIGN_TARGETS) clean