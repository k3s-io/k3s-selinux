# vim: sw=4:ts=4:et


%define k3s_relabel_files() \
mkdir -p /var/lib/cni; \
mkdir -p /var/lib/kubelet/pods; \
mkdir -p /var/lib/rancher/k3s/agent/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots; \
mkdir -p /var/lib/rancher/k3s/data; \
mkdir -p /var/run/flannel; \
mkdir -p /var/run/k3s; \
restorecon -R -i /etc/systemd/system/k3s.service; \
restorecon -R -i /usr/lib/systemd/system/k3s.service; \
restorecon -R /var/lib/cni; \
restorecon -R /var/lib/kubelet; \
restorecon -R /var/lib/rancher; \
restorecon -R /var/run/k3s; \
restorecon -R /var/run/flannel


%define selinux_policyver 20210716-3.1
%define container_policyver 2.164.2-1.1

Name:   k3s-selinux
Version:	%{k3s_selinux_version}
Release:	%{k3s_selinux_release}.sle
Summary:	SELinux policy module for k3s

Group:	System Environment/Base		
License:	ASL 2.0
URL:		http://k3s.io
Source0:	k3s.pp
Source1:	k3s.if

BuildArch: noarch
BuildRequires: container-selinux >= %{container_policyver}
BuildRequires: container-selinux < 2:2.164.2
BuildRequires: git
BuildRequires: selinux-policy-devel

Requires: policycoreutils, selinux-tools
Requires(post): selinux-policy-base >= %{selinux_policyver}, policycoreutils, container-selinux >= %{container_policyver}
Requires(postun): policycoreutils

Conflicts: rke2-selinux

%description
This package installs and sets up the SELinux policy security module for k3s.

%install
install -d %{buildroot}%{_datadir}/selinux/packages
install -m 644 %{SOURCE0} %{buildroot}%{_datadir}/selinux/packages
install -d %{buildroot}%{_datadir}/selinux/devel/include/contrib
install -m 644 %{SOURCE1} %{buildroot}%{_datadir}/selinux/devel/include/contrib/
install -d %{buildroot}/etc/selinux/targeted/contexts/users/

%pre
%selinux_relabel_pre

%post
%selinux_modules_install %{_datadir}/selinux/packages/k3s.pp
if /usr/sbin/selinuxenabled ; then
    /usr/sbin/load_policy
    %k3s_relabel_files
fi;

%postun
if [ $1 -eq 0 ]; then
    %selinux_modules_uninstall k3s
fi;

%posttrans
%selinux_relabel_post

%files
%attr(0600,root,root) %{_datadir}/selinux/packages/k3s.pp
%{_datadir}/selinux/devel/include/contrib/k3s.if


%changelog
* Mon Feb 24 2020 Darren Shepherd <darren@rancher.com> 1.0-1
- Initial version

