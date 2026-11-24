BUILD_TARGETS := $(addprefix build-,$(shell ls policy/))

# One Lima template per policy under hack/e2e/<policy>.yaml.
DISTROS := $(patsubst hack/e2e/%.yaml,%,$(wildcard hack/e2e/*.yaml))
E2E_TARGETS := $(addprefix e2e-,$(DISTROS))
LIMA_DEBUG ?=
LIMA_CPUS ?= 4
LIMA_MEMORY ?= 8
# Optional, defaults to the version pinned in hack/e2e/setup-vm.sh.
INSTALL_K3S_VERSION ?=

$(BUILD_TARGETS):
	rm -rf dist/$(@:build-%=%)
	docker buildx build \
      --target result --output=. \
      --build-arg TAG=${TAG} \
      --build-arg SCRIPT=build \
			-f Dockerfile.$(@:build-%=%) .

clean:
	rm -rf dist/

# Lima instance name, expanded within the e2e-% recipes.
VM = k3s-selinux-$*

e2e: $(E2E_TARGETS)

# Build the policy, then install it with K3s in a fresh VM (eg. make e2e-centos9).
# On failure the VM is kept for debugging: limactl shell k3s-selinux-<distro>
$(E2E_TARGETS): e2e-%:
	$(MAKE) build-$*

	-limactl delete -f $(VM) 2>/dev/null
	limactl start $(LIMA_DEBUG) --tty=false --cpus $(LIMA_CPUS) --memory $(LIMA_MEMORY) --plain \
		--name=$(VM) hack/e2e/$*.yaml

	limactl cp dist/$*/noarch/k3s-selinux-*.noarch.rpm $(VM):/tmp/k3s-selinux.rpm
	limactl cp hack/e2e/setup-vm.sh $(VM):/tmp/setup-vm.sh
	limactl shell $(VM) sudo \
		$(if $(INSTALL_K3S_VERSION),INSTALL_K3S_VERSION=$(INSTALL_K3S_VERSION)) /tmp/setup-vm.sh

	limactl delete -f $(VM)

$(addsuffix -clean,$(E2E_TARGETS)): e2e-%-clean:
	limactl delete -f $(VM)

.PHONY: $(BUILD_TARGETS) clean e2e $(E2E_TARGETS) $(addsuffix -clean,$(E2E_TARGETS))
