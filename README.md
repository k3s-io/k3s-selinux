# k3s-selinux
K3s selinux policy repository

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
| master (no tag) | Clean | `k3s-selinux-0.0~0d52f7d8-0.el7_8.noarch.rpm` | Testing ||
| master (no tag) | Dirty | `k3s-selinux-0.0~0d52f7d8-0.el7_8.noarch.rpm` | Testing ||
| v0.2.testing.1 | Clean | `k3s-selinux-0.2-1.el7_8.noarch.rpm` | Testing ||
| v0.2.latest.1 | Clean | `k3s-selinux-0.2-1.el7_8.noarch.rpm` | Latest ||
| v0.2.latest.2 | Clean | `k3s-selinux-0.2-2.el7_8.noarch.rpm` | Latest ||
