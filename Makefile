UPLOAD_TARGETS := $(addprefix upload-,$(shell ls policy/))
BUILD_TARGETS := $(addprefix build-,$(shell ls policy/))
SIGN_TARGETS := $(addprefix sign-,$(shell ls policy/))

$(BUILD_TARGETS):
	docker buildx build \
      --target result --output=. \
      --build-arg TAG=${TAG} \
      --build-arg SCRIPT=build \
			-f Dockerfile.$(@:build-%=%) .

$(SIGN_TARGETS):
	docker buildx build \
      --target result --output=. \
      --build-arg TAG=${TAG} \
      --build-arg SCRIPT=sign \
			-f Dockerfile.$(@:sign-%=%) .

$(UPLOAD_TARGETS):
	docker buildx build \
      --target result --output=. \
      --build-arg TAG=${TAG} \
      --build-arg SCRIPT=upload \
			-f Dockerfile.$(@:upload-%=%) .

clean:
	rm -rf dist/

.PHONY: $(UPLOAD_TARGETS) $(BUILD_TARGETS) $(SIGN_TARGETS) clean