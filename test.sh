#!/bin/bash
set -e

mkdir -p /opt/cni/bin/
touch cni.log

contid=$(printf '%x%x%x%x' $RANDOM $RANDOM $RANDOM $RANDOM)
netnspath=/var/run/netns/$contid
ip netns add $contid
CNI_COMMAND=ADD \
CNI_CONTAINERID=$contid \
CNI_NETNS=/var/run/netns/$contid \
CNI_IFNAME=eth0 \
./my-cni < cni-config

function cleanup() {
    CNI_COMMAND=DEL \
    CNI_CONTAINERID=$contid \
    CNI_NETNS=/var/run/netns/$contid \
    CNI_IFNAME=eth0 \
    ./my-cni < cni-config
  ip netns delete $contid
}

trap cleanup EXIT
ip netns exec $contid "$@"