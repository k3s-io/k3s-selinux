FROM centos:7 as build
COPY k3s.fc k3s.if k3s-selinux.spec k3s.sh k3s.te /

COPY scripts scripts
RUN scripts/build-setup

ARG TAG=v0+dev-docker
ENV TAG $TAG

RUN scripts/build

FROM scratch
COPY --from=build /dist/rpm/noarch/k3s-selinux-*.rpm ./
