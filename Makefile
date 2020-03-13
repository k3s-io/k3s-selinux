COMMIT ?= $(shell git rev-parse HEAD)

build:
	DOCKER_BUILDKIT=1 \
	docker build \
		--build-arg TAG=${TAG} \
		--build-arg COMMIT=${COMMIT} \
		-o ./dist .
