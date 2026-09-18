#!/bin/sh
set -u
export LD_LIBRARY_PATH=/lib:/nupp
export LUA_PATH='/nupp/?.lua;;'
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t devtmpfs devtmpfs /dev
/nupp/seed-entropy || exit 1
printf '\n@@NUPP_QEMU_READY@@\n'
/nupp/luajit /nupp/features.lua /nupp
result=$?
printf '\n@@NUPP_QEMU_EXIT@@ %s\n' "$result"
while :; do /bin/busybox sleep 3600; done
