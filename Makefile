BUILD_TARGETS := $(addprefix build-,$(shell ls policy/))

$(BUILD_TARGETS):
	rm -rf dist/$(@:build-%=%)
	docker buildx build \
      --target result --output=. \
      --build-arg TAG=${TAG} \
      --build-arg SCRIPT=build \
			-f Dockerfile.$(@:build-%=%) .

clean:
	rm -rf dist/

.PHONY: $(BUILD_TARGETS) clean
