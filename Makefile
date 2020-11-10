CENTOS7_TARGETS := $(addprefix centos7-,$(shell ls policy/centos7/scripts))
CENTOS8_TARGETS := $(addprefix centos8-,$(shell ls policy/centos8/scripts))

.dapper:
	@echo Downloading dapper
	@curl -sL https://releases.rancher.com/dapper/latest/dapper-$$(uname -s)-$$(uname -m) > .dapper.tmp
	@@chmod +x .dapper.tmp
	@./.dapper.tmp -v
	@mv .dapper.tmp .dapper

$(CENTOS7_TARGETS): .dapper
	./.dapper -f Dockerfile.centos7.dapper $(@:centos7-%=%)

$(CENTOS8_TARGETS): .dapper
	./.dapper -f Dockerfile.centos8.dapper $(@:centos8-%=%)

.PHONY: $(CENTOS7_TARGETS) $(CENTOS8_TARGETS)
