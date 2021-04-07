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


%define selinux_policyver 3.13.1-252

%if 0%{?el7}
	%define container_policyver 2.107-3
%else
	%define container_policyver 2.124.0-1
%endif

Name:		k3s-selinux
Version:	%{k3s_selinux_version}
Release:	%{k3s_selinux_release}%{?dist}
Summary:	SELinux policy module for k3s

Group:		System Environment/Base
License:	ASL 2.0
URL:		http://k3s.io

Source0:	Makefile
Source1:	k3s.fc
Source2:	k3s.if
Source3:	k3s.te

BuildRequires:	selinux-policy, selinux-policy-devel
Requires(post):	selinux-policy-base >= %{selinux_policyver}
Requires(post):	container-selinux >= %{container_policyver}
Requires(post):	policycoreutils
Requires(pre):	libselinux-utils
Requires(post):	libselinux-utils

Conflicts:	rke2-selinux

BuildArch:	noarch


%description
This package provides the SELinux policy module to ensure k3s
runs properly under an environment with SELinux enabled.


%prep
%setup -T -c
cp -a %{SOURCE0} %{SOURCE1} %{SOURCE2} %{SOURCE3} .


%build
make SHARE="%{_datadir}" TARGETS="k3s"


%install
install -Dpm 0644 k3s.if %{buildroot}%{_datadir}/selinux/devel/include/contrib/k3s.if
install -Dpm 0644 k3s.pp.bz2 %{buildroot}%{_datadir}/selinux/packages/k3s.pp.bz2


%pre
%selinux_relabel_pre

%post
%selinux_modules_install %{_datadir}/selinux/packages/k3s.pp.bz2
if /usr/sbin/selinuxenabled ; then
    /usr/sbin/load_policy
    %k3s_relabel_files

fi;
%selinux_relabel_post

%posttrans
%selinux_relabel_post

%postun
%selinux_modules_uninstall selinux
if [ $1 -eq 0 ]; then
    %selinux_relabel_post
fi

%files
%attr(0600,root,root) %{_datadir}/selinux/packages/k3s.pp.bz2
%{_datadir}/selinux/devel/include/contrib/k3s.if


%changelog
* Wed Apr 07 2021 Neal Gompa <ngompa13@gmail.com>
- Rewrite to align with SELinux policy module packaging guidelines

* Mon Feb 24 2020 Darren Shepherd <darren@rancher.com> 1.0-1
- Initial version

