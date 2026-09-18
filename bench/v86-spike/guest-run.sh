#!/bin/sh
set -u
export LD_LIBRARY_PATH=/lib:/nupp
export LUA_PATH='/nupp/?.lua;;'
export LUA_CPATH='/nupp/?.so;;'
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t devtmpfs devtmpfs /dev
exec </dev/ttyS0 >/dev/ttyS0 2>&1
/nupp/seed-entropy || exit 1
/bin/busybox stty -echo -icanon min 1 time 0
if /bin/busybox grep -q 'nupp.bridge=1' /proc/cmdline; then
    /bin/busybox mkdir -p /host
    [ -e /dev/mem ] || /bin/busybox mknod /dev/mem c 1 1
    printf '\n@@NUPP_BRIDGE_READY@@\n'
    /nupp/luajit /nupp/bridge.lua
else
    printf '\n@@NUPP_QEMU_READY@@\n'
    /nupp/luajit /nupp/features.lua /nupp
fi
result=$?
printf '\n@@NUPP_QEMU_EXIT@@ %s\n' "$result"
while :; do /bin/busybox sleep 3600; done
