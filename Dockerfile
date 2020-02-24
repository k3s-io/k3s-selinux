FROM centos:7 as build
RUN yum install -y yum-utils
RUN yum-builddep -y container-selinux
RUN yum install -y rpm-build
COPY k3s.fc k3s.if k3s_selinux.spec k3s.sh k3s.te /
RUN make -f /usr/share/selinux/devel/Makefile k3s.pp && \
    pwd=$(pwd) && \
    rpmbuild --define "_sourcedir ${pwd}" \
             --define "_specdir ${pwd}" \
             --define "_builddir ${pwd}" \
             --define "_srcrpmdir ${pwd}" \
             --define "_rpmdir ${pwd}" \
             --define "_buildrootdir \
             ${pwd}/.build" -ba k3s_selinux.spec

FROM scratch
COPY --from=build /k3s_selinux-1.0-1.el7.src.rpm /noarch/k3s_selinux-1.0-1.el7.noarch.rpm .
