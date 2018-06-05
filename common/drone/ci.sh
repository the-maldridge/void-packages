#!/bin/bash

CI_MIRROR=alpha.de.repo.voidlinux.org
CI_PROTO=http

TARGET=$1
BOOTSTRAP=x86_64
# Switch based on build host.  The configuration here needs to match
# what the real build machines use, otherwise the CI isn't much
# good...
case $TARGET in
    *-musl) BOOTSTRAP=x86_64-musl ;;
    i686) BOOTSTRAP=i686 ;;
esac

echo "Starting xbps-src CI run"

echo "Configuring CI mirror settings"
for _i in etc/repos-remote.conf etc/defaults.conf etc/repos-remote-x86_64.conf ; do
    printf '\x1b[32mUpdating %s...\x1b[0m\n' $_i
    # First fix the proto, ideally we'd serve everything with HTTPS,
    # but key management and rotation is a pain, and things are signed
    # so we can afford to be a little lazy at times.
    sed -i "s:https:$CI_PROTO:g" $_i

    # Now set the mirro
    sed -i "s:repo\.voidlinux\.eu:$CI_MIRROR:g" $_i
done

echo "Installing xtools"
xbps-install -Sy xtools git proot bubblewrap

echo "Configuring etc/conf"
echo XBPS_MAKEJOBS=4 >> etc/conf
echo XBPS_ALLOW_RESTRICTED=yes >> etc/conf
echo XBPS_CHROOT_CMD=bwrap >> etc/conf

echo "Fetching upstream..."
git fetch --depth 200 git://github.com/voidlinux/void-packages.git master

echo "Changed packages:"
git diff --name-status FETCH_HEAD...HEAD | grep "^[AM].*srcpkgs/[^/]*/template$" | cut -d/ -f 2 | tee /tmp/templates | sed "s/^/  /" >&2

echo "Running xlint"
awk '{ print "srcpkgs/" $0 "/template" }' /tmp/templates | xargs xlint

echo "Bootstrapping the build chroot"
./xbps-src -H $HOME/hostdir binary-bootstrap $BOOTSTRAP

echo "Building packages for $TARGET"
PKGS=$(./xbps-src sort-dependencies $(cat /tmp/templates))
for pkg in ${PKGS}; do
    if [ $TARGET != $BOOTSTRAP ] ; then
	./xbps-src -H $HOME/hostdir -a $TARGET pkg "$pkg"
    else
        ./xbps-src -H $HOME/hostdir pkg "$pkg"
    fi
    [ $? -eq 1 ] && exit 1
done

echo "Showing Files"
export XBPS_TARGET_ARCH="$TARGET"
for pkg in $(cat /tmp/templates); do
	for subpkg in $(xsubpkg $pkg); do
		echo "Files of $subpkg:"
		xbps-query --repository=$HOME/hostdir/binpkgs -f "$subpkg"
	done
done
