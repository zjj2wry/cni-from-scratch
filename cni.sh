#!/bin/bash
set -euo
# CNI_COMMAND: ADD DEL VERSION
# CNI_CONTAINERID:
# CNI_NETNS:
# CNI_IFNAME: IFNAME created in container
# CNI_PATH:

# sudo CNI_COMMAND=ADD \
# CNI_CONTAINERID=ns1 \
# CNI_NETNS=/var/run/netns/ns1 \
# CNI_IFNAME=eth0 \
# CNI_PATH=$GOPATH/src/github.com/containernetworking/plugins/bin ./cni

usage() {
cat << EOF
implement a simple kubernetes cni by shell.
Available CNI_COMMAND env:
  ADD        add a container network
  DEL        delete a container network
  VERSION    show cni version
EOF
}

add() {
  echo ${CNI_COMMAND}
}

del() {
    "Not Implement"
}

version() {
    "Not Implement"
}

case "${CNI_COMMAND}" in
  ADD)
    add
    ;;
  DEL)
    del
    ;;
  VERSION)
    version
    ;;
  *)
    usage
    exit 1
    ;;
esac