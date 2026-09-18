#!/bin/sh
set -u
export LD_LIBRARY_PATH=/lib:/nupp
export LUA_PATH='/nupp/?.lua;;'
export LUA_CPATH='/nupp/?.so;;'
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t devtmpfs devtmpfs /dev
/nupp/seed-entropy || exit 1
/bin/busybox stty -echo -icanon min 1 time 0
if /bin/busybox grep -q 'nupp.bridge=1' /proc/cmdline; then
    for module in netfs 9pnet 9pnet_virtio 9p; do
        /bin/busybox insmod "/nupp/modules/$module.ko" || exit 1
    done
    /bin/busybox mkdir -p /host
    [ -e /dev/mem ] || /bin/busybox mknod /dev/mem c 1 1
    /bin/busybox mount -t 9p -o trans=virtio,version=9p2000.L,cache=none host /host || exit 1
    printf '\n@@NUPP_BRIDGE_READY@@\n'
    /nupp/luajit /nupp/bridge.lua
    result=$?
    printf '\n@@NUPP_QEMU_EXIT@@ %s\n' "$result"
    while :; do /bin/busybox sleep 3600; done
fi
printf '\n@@NUPP_QEMU_READY@@\n'
/nupp/luajit /nupp/features.lua /nupp
result=$?
printf '\n@@NUPP_QEMU_EXIT@@ %s\n' "$result"
while :; do /bin/busybox sleep 3600; done
