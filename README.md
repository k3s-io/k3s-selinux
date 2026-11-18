# k3s-selinux
K3s selinux policy repository.

## Signing Keys

- https://rpm.rancher.io/public.key
- https://rpm-testing.rancher.io/public.key

## Versioning/Tagging

The version parsing logic for `rancher/k3s-selinux` expects tags to be of a certain format (that directly correlates to RPM naming)

The tag format should be as follows: `v{k3s-selinux-version}.{rpm channel}.{rpm release}` where 

k3s-selinux-version is like `0.1`, `0.2`, etc.
rpm channel is like `testing`, `latest`, `stable`
rpm release is like `1`, `2`

rpm release should index from `1` for released RPM's

The following list shows the expected tag to (example) transformation for RPM's

|Tag|Tree State|Output RPM|RPM Channel|Notes|
|:--|:---------|:---------|:----------|:----|
| master (no tag) | Clean | `k3s-selinux-0.2~0d52f7d8-0.el7_8.noarch.rpm` | Testing | Based on the latest tag (`0.0` without tags) |
| master (no tag) | Dirty | `k3s-selinux-0.2~0d52f7d8dirty-0.el7_8.noarch.rpm` | Testing | Based on the latest tag (`0.0` without tags) |
| v0.2.testing.1 | Clean | `k3s-selinux-0.2-1.el7_8.noarch.rpm` | Testing ||
| v0.2.latest.1 | Clean | `k3s-selinux-0.2-1.el7_8.noarch.rpm` | Latest ||
| v0.2.latest.2 | Clean | `k3s-selinux-0.2-2.el7_8.noarch.rpm` | Latest ||

## Development

Building requires Docker with `buildx`. End-to-end tests require [Lima](https://lima-vm.io) and QEMU.

| Command                      | Description                                                 |
| :--------------------------- | :---------------------------------------------------------- |
| `make build-<policy>`        | Build a single policy (e.g. `make build-centos9`)           |
| `make e2e`                   | Run end-to-end tests for all policies                       |
| `make e2e-<policy>`          | Run end-to-end tests in a VM (e.g. `make e2e-centos9`)      |
| `make e2e-<policy>-clean`    | Delete the VM left behind by a failed run                   |

Artefacts are written to `dist/<policy>/`.

The end-to-end test (`hack/e2e/setup-vm.sh`) builds the policy, boots a VM from `hack/e2e/<policy>.yaml`,
installs the RPM, installs K3s with `selinux: true` and embedded etcd, runs a pod on a `local-path`
volume and checks that:

- the RPM and the `k3s` module are installed and its types are known;
- K3s (with the embedded kubelet, apiserver and etcd), containerd and the shims run as
  `container_runtime_t`, and pods as `container_t`;
- K3s files (binaries, data dir, containerd state, local-path storage, etcd data and snapshots, logs)
  have the expected labels;
- there are no AVC denials involving `container_runtime_t` or `k3s_*` types.

Every policy has an end-to-end test except `slemicro` (SLE Micro 5.x): there is no freely available
cloud-init image for it, and it is transactional. Some policies are tested on a related distribution:

- `sle` (SLES 16 / SL Micro 6.x) on openSUSE Leap 16, which shares their base.
- `coreos` (Fedora CoreOS) on Fedora Cloud of the same release: Fedora CoreOS is provisioned with
  Ignition, which Lima does not support, and layers packages with rpm-ostree.

Use `INSTALL_K3S_VERSION` to test against another K3s release (e.g. `make e2e-centos9 INSTALL_K3S_VERSION=v1.36.6+k3s1`).
