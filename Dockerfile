FROM centos:7 as build
COPY k3s.fc k3s.if k3s-selinux.spec k3s.sh k3s.te scripts/build* /

ARG DEV_RELEASE
ENV DEV_RELEASE $DEV_RELEASE

RUN ./build-setup
RUN ./build

FROM scratch
COPY --from=build /dist/rpm/noarch/k3s-selinux-*.rpm ./
