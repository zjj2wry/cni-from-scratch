#!/bin/bash
# set -e

declare -A map

for i in {0..2}
do
  nodeip=$(kubectl get nodes -o jsonpath="{.items[${i}].status.addresses[0].address}")
  podcidr=$(kubectl get nodes -o jsonpath="{.items[${i}].spec.podCIDR}")
  echo "nodeip: "$nodeip", podcidr: "$podcidr""
  map["$nodeip"]="$podcidr"
done

writeConfig(){
  podcidr=${map["${HOST_IP}"]}

  template='{
      "cniVersion": "0.3.0",
      "name": "my-cni",
      "type": "my-cni",
      "podcidr": "%s"
  }'
  mkdir -p /etc/cni/net.d/
  printf "${template}" $podcidr > /etc/cni/net.d/cni-config.conf
  cat /etc/cni/net.d/cni-config.conf
  mkdir -p /opt/cni/
  cp my-cni /opt/cni/bin
  # for debug
  cp test.sh /opt/cni/bin
}

init(){
  echo 1 > /proc/sys/net/ipv4/ip_forward
  iptables -t nat -N masq > /dev/null 2>&1
  for k in "${!map[@]}"
  do
      echo "init iptables rules, "${map[$k]}""
      iptables -t nat -A masq -d ${map[$k]} -j RETURN
  done
  iptables -t nat -A masq  -j MASQUERADE
  iptables -t nat -A POSTROUTING -m addrtype ! --dst-type LOCAL -j masq
}

syncRoute(){
  for k in "${!map[@]}"
  do
      if [ "$k" != "${HOST_IP}" ]; then
        echo "init ip route, "${map[$k]}", "$k""
        ip route add "${map[$k]}" via "$k" > /dev/null 2>&1
      fi
  done
}

writeConfig
init
syncRoute
rm /opt/cni/bin/cni.log > /dev/null 2>&1
touch /opt/cni/bin/cni.log
tail -f /opt/cni/bin/cni.log
