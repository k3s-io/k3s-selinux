#!/bin/sh -e

DIRNAME=`dirname $0`
cd $DIRNAME

echo "Building and Loading Policy"
set -x
make -f /usr/share/selinux/devel/Makefile k3s.pp || exit
/usr/sbin/semodule -i k3s.pp

/sbin/restorecon -F -R -v /usr/local/bin
/sbin/restorecon -F -R -v /var/run
/sbin/restorecon -F -R -v /var/lib

pwd=$(pwd)
rpmbuild --define "_sourcedir ${pwd}" --define "_specdir ${pwd}" --define "_builddir ${pwd}" --define "_srcrpmdir ${pwd}" --define "_rpmdir ${pwd}" --define "_buildrootdir ${pwd}/.build"  -ba k3s_selinux.spec
