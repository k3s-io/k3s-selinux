#!/bin/bash
#
# End-to-end test for k3s-selinux. Runs as root inside a fresh VM (see Makefile e2e-% target):
#   1. installs the locally built RPM from /tmp/k3s-selinux.rpm;
#   2. installs K3s with SELinux enabled and waits for the cluster to be ready;
#   3. runs a pod on a local-path volume;
#   4. verifies process and file contexts and fails on any AVC denial involving K3s types.

set -euxo pipefail

# Override with: make e2e-<distro> INSTALL_K3S_VERSION=vX.Y.Z+k3sN
INSTALL_K3S_VERSION="${INSTALL_K3S_VERSION:-v1.35.10+k3s1}"

RPM_PATH=/tmp/k3s-selinux.rpm
K3S_DATA_DIR=/var/lib/rancher/k3s

# The installer puts k3s and the kubectl symlink in /usr/local/bin, which is not in sudo's
# secure_path on EL.
export PATH="${PATH}:/usr/local/bin"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Denials whose source or target is one of these types are attributed to k3s-selinux
# and fail the test. K3s itself (with the embedded kubelet, apiserver and etcd) and
# containerd run as container_runtime_t.
AVC_PATTERN='context=[^ ]*:(container_runtime_t|k3s_[a-z0-9_]+):'

function fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# Checks that can run independently record their failures here instead of exiting, so a single run
# reports every unexpected label and AVC denial. reportErrors fails the test at the end.
ERRORS=()

function addError() {
    echo "ERROR: $*" >&2
    ERRORS+=("$*")
}

function reportErrors() {
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        fail "${#ERRORS[@]} check(s) failed:"$'\n'"$(printf -- '- %s\n' "${ERRORS[@]}")"
    fi
    echo "All checks passed."
}

function isSUSE() {
    grep -qi "suse" /etc/os-release
}

function dumpDiagnostics() {
    set +e
    echo "> Diagnostics"
    getenforce
    kubectl get nodes,pods,pvc,pv -A -o wide
    kubectl get events -A --sort-by=.lastTimestamp
    local pod
    for pod in $(kubectl get pods -A --no-headers \
        -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,READY:.status.containerStatuses[*].ready,PHASE:.status.phase |
        awk '$4 != "Succeeded" && $3 ~ /false|<none>/ {print $1 "/" $2}'); do
        kubectl describe pod -n "${pod%%/*}" "${pod#*/}"
        kubectl logs -n "${pod%%/*}" "${pod#*/}" --all-containers --prefix --tail=50
    done
    lsmod
    journalctl -u k3s --no-pager | tail -n 200
    ausearch -m AVC,USER_AVC,SELINUX_ERR -ts boot
}

function checkSELinuxEnforcing() {
    echo "> Check SELinux status"
    getenforce | grep -qx Enforcing || fail "SELinux is not enforcing: $(getenforce)"
}

function installPolicy() {
    echo "> Installing k3s-selinux from ${RPM_PATH}"
    if isSUSE; then
        zypper -n --gpg-auto-import-keys install audit setools-console
        systemctl enable --now auditd
        # Install k3s-selinux on its own, as users would: container-selinux is pulled in as a
        # dependency in the same transaction, so scriptlet ordering issues are caught.
        zypper -n --gpg-auto-import-keys install --allow-unsigned-rpm "${RPM_PATH}"
    else
        local rhel
        rhel=$(rpm -E '%{?rhel}')
        if [[ -z "${rhel}" ]]; then
            # Fedora Cloud only ships kernel-core, without the netfilter modules needed by K3s.
            # The release repository keeps the kernel of the pinned image.
            dnf install -y "kernel-modules-$(uname -r)"
        elif [[ "${rhel}" -ge 10 ]]; then
            # RHEL 10 moved netfilter modules needed by K3s (nf_conntrack) to kernel-modules-extra.
            dnf install -y "kernel-modules-extra-$(uname -r)"
        fi
        # Test against the latest container-selinux and selinux-policy available for the distro.
        dnf install -y --best --allowerasing container-selinux selinux-policy
        dnf install -y audit setools-console
        systemctl enable --now auditd
        dnf install -y "${RPM_PATH}"
    fi
}

function verifyPolicy() {
    echo "> Verify k3s-selinux installation"
    local expected installed
    expected=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}' "${RPM_PATH}")
    installed=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}' k3s-selinux) || fail "k3s-selinux RPM is not installed"
    [[ "${installed}" == "${expected}" ]] || fail "installed ${installed}, expected ${expected}"

    # The spec scriptlets exit 0 on failure, so check the module was actually loaded.
    semodule -l | awk '{print $1}' | grep -qx k3s || fail "k3s SELinux module not loaded"

    local t
    for t in k3s_data_t k3s_lock_t k3s_root_t k3s_db_t; do
        seinfo -t "${t}" | grep -qw "${t}" || fail "SELinux type ${t} unknown"
    done
    echo "k3s-selinux ${installed} verified."
}

function installK3s() {
    echo "> Installing K3s ${INSTALL_K3S_VERSION}"
    mkdir -p /etc/rancher/k3s
    # cluster-init: run the embedded etcd instead of SQLite, to cover etcd and its snapshots.
    cat > /etc/rancher/k3s/config.yaml <<EOF
selinux: true
cluster-init: true
write-kubeconfig-mode: "0644"
EOF
    # EL8 boots with cgroup v1, which the kubelet refuses by default since Kubernetes 1.35.
    if [[ "$(stat -fc %T /sys/fs/cgroup)" != "cgroup2fs" ]]; then
        echo 'kubelet-arg: ["fail-cgroupv1=false"]' >> /etc/rancher/k3s/config.yaml
    fi

    # Skip the RPM: the installer would replace the local k3s-selinux with the one from
    # rpm.rancher.io.
    curl -sfL https://get.k3s.io -o /tmp/install.sh
    INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_SKIP_START=true \
        INSTALL_K3S_VERSION="${INSTALL_K3S_VERSION}" sh /tmp/install.sh
    rm -f /tmp/install.sh
    # With INSTALL_K3S_SKIP_SELINUX_RPM the installer does not label the binary either: it keeps the
    # label of its download directory (user_tmp_t), which systemd cannot execute. Label it from the
    # file context database, as users skipping the RPM have to.
    restorecon -v /usr/local/bin/k3s

    # k3s is Type=notify: start returns once the apiserver is up and the kubeconfig written.
    # The unit has no start timeout, so bound it here to get diagnostics instead of a hung job.
    timeout 600 systemctl start k3s.service || fail "k3s did not become ready"
}

function waitForCluster() {
    echo "> Waiting for the cluster to be ready"
    local node d
    node=$(hostname)
    kubectl wait --for=create "node/${node}" --timeout=240s
    kubectl wait --for=condition=ready "node/${node}" --timeout=300s

    for d in coredns local-path-provisioner metrics-server; do
        kubectl wait --for=create -n kube-system "deployment/${d}" --timeout=240s
        kubectl rollout status -n kube-system "deployment/${d}" --timeout=300s
    done

    # Helm install jobs for the packaged charts (traefik), then every workload they created.
    kubectl wait --for=create -n kube-system job/helm-install-traefik --timeout=240s
    kubectl wait --for=condition=complete -n kube-system job --all --timeout=600s
    kubectl wait --for=condition=ready -n kube-system pod --all \
        --field-selector=status.phase!=Succeeded,status.phase!=Failed --timeout=300s

    kubectl get nodes,pods -A -o wide
}

# Write to a local-path volume: the provisioner creates the volume directory under
# ${K3S_DATA_DIR}/storage, and the pod (container_t) must be able to write into it.
function runVolumeWorkload() {
    echo "> Run a pod on a local-path volume"
    local image
    # Reuse the image of the local-path helper pod, already pulled by the provisioner.
    image=$(kubectl get configmap -n kube-system local-path-config -o jsonpath='{.data.helperPod\.yaml}' |
        awk '$1 == "image:" {print $2; exit}')
    [[ -n "${image}" ]] || fail "could not find the local-path helper pod image"

    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: e2e
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources:
    requests:
      storage: 16Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: e2e
  namespace: default
spec:
  restartPolicy: Never
  containers:
  - name: writer
    image: ${image}
    command: [sh, -c, "echo e2e > /data/e2e && cat /data/e2e"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: e2e
EOF
    kubectl wait --for=jsonpath='{.status.phase}'=Succeeded -n default pod/e2e --timeout=300s ||
        fail "pod e2e did not succeed: $(kubectl logs -n default pod/e2e 2>&1)"
    kubectl logs -n default pod/e2e
}

# checkProcessContext PROCESS_NAME EXPECTED_TYPE
# Every running process with that name must run in EXPECTED_TYPE.
function checkProcessContext() {
    local proc="$1" expected="$2"
    local labels label
    # ps truncates comm to 15 characters (e.g. containerd-shim-runc-v2).
    labels=$(ps -eo label=,comm= | awk -v p="${proc:0:15}" '$2 == p {print $1}' | sort -u)
    [[ -n "${labels}" ]] || fail "no running process named ${proc}"

    for label in ${labels}; do
        [[ "$(cut -d: -f3 <<<"${label}")" == "${expected}" ]] || fail "process ${proc} runs as ${label}, expected type ${expected}"
    done
    echo "process ${proc}: ${expected}"
}

# canonicalType TYPE: print the primary name of TYPE, which may be an alias. Labels always show the
# primary name, e.g. container_share_t is an alias of container_ro_file_t in recent container-selinux.
function canonicalType() {
    local primary
    primary=$(seinfo -t "$1" 2>/dev/null | awk '/^ +[a-z]/ {print $1; exit}')
    echo "${primary:-$1}"
}

# checkFileContext EXPECTED_TYPE PATH...
function checkFileContext() {
    local expected path ctx
    expected=$(canonicalType "$1"); shift
    for path in "$@"; do
        if ! ctx=$(stat -c %C "${path}"); then
            addError "${path} does not exist"
        elif [[ "$(cut -d: -f3 <<<"${ctx}")" != "${expected}" ]]; then
            addError "${path} is labeled ${ctx}, expected type ${expected}"
        else
            echo "file ${path}: ${expected}"
        fi
    done
}

function verifyProcessContexts() {
    echo "> Verify process contexts"
    # /usr/local/bin/k3s re-executes itself from the data dir as k3s-server.
    checkProcessContext k3s-server container_runtime_t
    checkProcessContext containerd container_runtime_t
    checkProcessContext containerd-shim-runc-v2 container_runtime_t
    checkProcessContext coredns container_t
}

function verifyFileContexts() {
    echo "> Verify file contexts"
    local data
    data=$(readlink -f ${K3S_DATA_DIR}/data/current) || fail "${K3S_DATA_DIR}/data/current does not exist"

    checkFileContext container_runtime_exec_t /usr/local/bin/k3s \
        "${data}"/bin/{containerd-shim-runc-v2,runc,cni}
    checkFileContext container_unit_file_t /etc/systemd/system/k3s.service
    checkFileContext container_var_lib_t ${K3S_DATA_DIR} ${K3S_DATA_DIR}/server
    checkFileContext k3s_db_t ${K3S_DATA_DIR}/server/db ${K3S_DATA_DIR}/server/db/etcd
    checkFileContext k3s_data_t ${K3S_DATA_DIR}/data ${K3S_DATA_DIR}/data/cni "${data}" "${data}"/bin/{.links,.sha256sums}
    checkFileContext k3s_lock_t ${K3S_DATA_DIR}/data/.lock
    # bin/containerd, k3s-server, kubectl... are symlinks to this multicall binary.
    checkFileContext k3s_root_t "${data}"/bin "${data}"/bin/k3s
    checkFileContext container_config_t "${data}"/etc

    # container-selinux names "snapshots" directories container_file_t when they are created, and
    # restorecon does not reset this customizable type: the sle and slemicro file contexts
    # (container_share_t) never apply.
    checkFileContext container_file_t ${K3S_DATA_DIR}/agent/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots
    checkFileContext container_share_t ${K3S_DATA_DIR}/agent/containerd/io.containerd.grpc.v1.cri/sandboxes
    checkFileContext container_file_t ${K3S_DATA_DIR}/storage ${K3S_DATA_DIR}/storage/pvc-*_default_e2e{,/e2e}
    checkFileContext container_var_run_t /run/k3s /run/k3s/containerd
    checkFileContext container_log_t /var/log/pods /var/log/containers
    # The spec scriptlets create /var/lib/kubelet/pods and restore it to its file context
    # (container_var_lib_t), so the "pods" type transition to container_file_t does not apply.
    checkFileContext container_var_lib_t /var/lib/kubelet /var/lib/kubelet/pods

    # Informational: list paths whose type differs from the file context database.
    restorecon -Rnv ${K3S_DATA_DIR} /var/lib/kubelet /run/k3s || true
}

function verifyEtcdSnapshot() {
    echo "> Verify etcd snapshot"
    k3s etcd-snapshot save --name e2e
    # Created under server/db (k3s_db_t), so container-selinux's "snapshots" type transition to
    # container_file_t does not apply.
    checkFileContext k3s_db_t ${K3S_DATA_DIR}/server/db/snapshots ${K3S_DATA_DIR}/server/db/snapshots/e2e-*
}

function verifyNoAVCs() {
    echo "> Look for AVC denials"
    local avcs relevant
    avcs=$(ausearch -m AVC,USER_AVC,SELINUX_ERR -ts boot 2>/dev/null || true)
    if [[ -n "${avcs}" ]]; then
        echo "All AVCs since boot (informational):"
        echo "${avcs}"
    fi

    relevant=$(grep -E "${AVC_PATTERN}" <<<"${avcs}" || true)
    if [[ -n "${relevant}" ]]; then
        addError "AVC denials involving K3s types:"$'\n'"${relevant}"
    else
        echo "No AVC denials involving K3s types."
    fi
}

function main() {
    checkSELinuxEnforcing
    installPolicy
    verifyPolicy
    installK3s
    waitForCluster
    runVolumeWorkload
    verifyProcessContexts
    verifyFileContexts
    verifyEtcdSnapshot
    verifyNoAVCs
    reportErrors
}

trap 'rc=$?; if [[ ${rc} -ne 0 ]]; then dumpDiagnostics; fi; exit ${rc}' EXIT

main
