# cni-from-scratch

## 背景
kubernetes 网络遵守下面几条限制：
- 所有的容器可以和其他的容器通信不需要 NAT
- 节点可以和其他的容器通信不需要 NAT
- 容器看到自己的 IP 和别人看到的 IP 是一样的

## cni
cni 是统一的容器网络插件接口，主要职责是解决容器网络的互通和回收。

5 个环境变量和一个配置文件:

CNI_COMMAND
```
cni 执行的命令，kubelet 会通过环境变量传给 cni，目前有 ADD、DELETE、CHECK 等命令，kubelet 会在创建容器的时候告诉 cni 做什么
```

CNI_CONTAINERID
```
容器的 ID
```

CNI_NETNS
```
容器的 network namespace 
```

CNI_IFNAME
```
容器中网卡的名称，一般是 eth0
```

CNI_PATH
```
cni 插件中可执行程序的目录
```

kubelet 有 3 个 flag 关于 cni 程序，```-network-plugin=cni``` 指定使用 cni 网络插件，```--cni-config-dir``` 指定 cni 配置文件，```--cni-bin-dir``` 存放 cni 可执行程序，kubelet 根据 config 里的 type 执行同名的二进制程序，然后传递上面的环境变量以及通过 stdin 把 config 信息给 cni 执行程序。
```bash
sudo CNI_COMMAND=ADD \
CNI_CONTAINERID=$contid \
CNI_NETNS=/var/run/netns/$contid \
CNI_IFNAME=eth0 \
./cni.sh < config
```

配置信息：
```bash
$ mkdir -p /etc/cni/net.d
$ cat >/etc/cni/net.d/10-mynet.conf <<EOF
{
	"cniVersion": "0.2.0",
	"name": "mynet",
	"type": "bridge",
	"bridge": "cni0",
	"isGateway": true,
	"ipMasq": true,
	"ipam": {
		"type": "host-local",
		"subnet": "10.22.0.0/16",
		"routes": [
			{ "dst": "0.0.0.0/0" }
		]
	}
}
EOF
$ cat >/etc/cni/net.d/99-loopback.conf <<EOF
{
	"cniVersion": "0.2.0",
	"name": "lo",
	"type": "loopback"
}
EOF
```

## pod 网络
细化一下 cni 需要解决下面几个问题：
- pod 的 ip 地址分配
- 同主机的 pod 网络互通
- pod 和宿主机的网络互通
- 跨主机的 pod 网络互通

下面通过 shell 实现一个基于 linux bridge + 简化版 host-local ip 地址分配 + 简化版 host route(主机路由) 来实现一个简化版的 cni，最后通过 kind(kubernetes in docker) 来部署 cni。

1. 创建 linux bridge
```bash
root@vagrant:/vagrant# ip link add cni0 type bridge
# 先手动分配一个 ip 给 bridge，假设 spec.podCIDR 是 10.0.0.0/24，每个节点有 256 个 pod IP 可以
# 使用，肯定是够用的
root@vagrant:/vagrant# ip addr add 10.0.0.1/24 dev cni0
root@vagrant:/vagrant# ip link set cni0 up
root@vagrant:/vagrant# ip link show cni0
3: cni0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/ether be:02:75:4f:40:b4 brd ff:ff:ff:ff:ff:ff
```

2. 创建 veth pair, 一端连在 bridge cni0 上，一端连在容器的 network namespace 上。

```bash
# cni 本身是不需要创建 net ns 的，这里为了测试先自己手动创建
root@vagrant:/vagrant# ip netns add ns1
root@vagrant:/vagrant# ip link add dev veth1 type veth peer name veth1c
root@vagrant:/vagrant# ip link set dev veth1 up
# veth1 挂在 cni0 的网桥上
root@vagrant:/vagrant# ip link set veth1 master cni0
# veth1c 挂在 ns1 上
root@vagrant:/vagrant# ip link set veth1c netns ns1
root@vagrant:/vagrant# ip netns exec ns1 ip link set veth1c name eth0
root@vagrant:/vagrant# ip netns exec ns1 ip link set dev lo up
# 继续手动分配一个 IP
root@vagrant:/vagrant# ip netns exec ns1 ip addr add 10.0.0.2/24 dev eth0
root@vagrant:/vagrant# ip netns exec ns1 ip link set dev eth0 up
# 设置 cni0 为 ns1 的默认网关，容器网络访问 host 网络
root@vagrant:/vagrant# ip netns exec ns1 ip route add default via 10.0.0.1
```

验证容器网络和宿主机网络的连通性

**host --> container**：

```bash
root@vagrant:/home/vagrant# ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 08:00:27:6b:c1:df brd ff:ff:ff:ff:ff:ff
    inet 10.0.2.15/24 brd 10.0.2.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::a00:27ff:fe6b:c1df/64 scope link
       valid_lft forever preferred_lft forever
3: cni0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether ce:b1:90:a5:e9:89 brd ff:ff:ff:ff:ff:ff
    inet 10.0.0.1/24 scope global cni0
       valid_lft forever preferred_lft forever
    inet6 fe80::bc02:75ff:fe4f:40b4/64 scope link
       valid_lft forever preferred_lft forever
7: veth1@if6: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master cni0 state UP group default qlen 1000
    link/ether ce:b1:90:a5:e9:89 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet6 fe80::ccb1:90ff:fea5:e989/64 scope link
       valid_lft forever preferred_lft forever
# 10.0.0.0/24 这条网关路由好像是 linux 自动创建的
root@vagrant:/home/vagrant# ip route
default via 10.0.2.2 dev eth0
10.0.0.0/24 dev cni0  proto kernel  scope link  src 10.0.0.1
10.0.2.0/24 dev eth0  proto kernel  scope link  src 10.0.2.15
root@vagrant:/home/vagrant# ping 10.0.0.2
PING 10.0.0.2 (10.0.0.2) 56(84) bytes of data.
64 bytes from 10.0.0.2: icmp_seq=1 ttl=64 time=0.048 ms
64 bytes from 10.0.0.2: icmp_seq=2 ttl=64 time=0.053 ms
64 bytes from 10.0.0.2: icmp_seq=3 ttl=64 time=0.053 ms
--- 10.0.0.2 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2001ms
rtt min/avg/max/mdev = 0.048/0.051/0.053/0.006 ms
```

**container --> host**：

```bash
root@vagrant:/home/vagrant# ip netns exec ns1 ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
6: eth0@if7: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether aa:c5:2c:db:6c:29 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.0.0.2/24 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::a8c5:2cff:fedb:6c29/64 scope link
       valid_lft forever preferred_lft forever
root@vagrant:/home/vagrant# ip netns exec ns1 ip route
default via 10.0.0.1 dev eth0
10.0.0.0/24 dev eth0  proto kernel  scope link  src 10.0.0.2
root@vagrant:/home/vagrant# ip netns exec ns1 ping 10.0.2.15
PING 10.0.2.15 (10.0.2.15) 56(84) bytes of data.
64 bytes from 10.0.2.15: icmp_seq=1 ttl=64 time=0.053 ms
64 bytes from 10.0.2.15: icmp_seq=2 ttl=64 time=0.056 ms
64 bytes from 10.0.2.15: icmp_seq=3 ttl=64 time=0.053 ms
--- 10.0.2.15 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2001ms
rtt min/avg/max/mdev = 0.053/0.054/0.056/0.001 ms
```

3. pod 和 pod 的网络互通，后面创建一个新的 pod 和上面的步骤一样，只需要分配一个 ip 地址给 pod，linux bridge 即可以用于解决二层网络互通，又可以给它分配 IP 作为 3层的网关来使用

```bash
# cni 本身是不需要创建 net ns 的，这里为了测试先自己手动创建
root@vagrant:/vagrant# ip netns add ns2
root@vagrant:/vagrant# ip link add dev veth2 type veth peer name veth2c
root@vagrant:/vagrant# ip link set dev veth2 up
# veth1 挂在 cni0 的网桥上
root@vagrant:/vagrant# ip link set veth2 master cni0
# veth1c 挂在 ns2 上
root@vagrant:/vagrant# ip link set veth2c netns ns2
root@vagrant:/vagrant# ip netns exec ns2 ip link set veth2c name eth0
root@vagrant:/vagrant# ip netns exec ns2 ip link set dev lo up
# 继续手动分配一个 IP
root@vagrant:/vagrant# ip netns exec ns2 ip addr add 10.0.0.3/24 dev eth0
root@vagrant:/vagrant# ip netns exec ns2 ip link set dev eth0 up
# 设置 cni0 为 ns1 的默认网关，容器网络访问 host 网络
root@vagrant:/vagrant# ip netns exec ns2 ip route add default via 10.0.0.1
```

**相同主机的 pod <--> pod**:

```bash
root@vagrant:/home/vagrant# ip netns exec ns2 ping 10.0.0.2
PING 10.0.0.2 (10.0.0.2) 56(84) bytes of data.
64 bytes from 10.0.0.2: icmp_seq=1 ttl=64 time=0.078 ms
64 bytes from 10.0.0.2: icmp_seq=2 ttl=64 time=0.053 ms
64 bytes from 10.0.0.2: icmp_seq=3 ttl=64 time=0.054 ms
--- 10.0.0.2 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2001ms
rtt min/avg/max/mdev = 0.053/0.061/0.078/0.014 ms
root@vagrant:/home/vagrant# ip netns exec ns1 ping 10.0.0.3
PING 10.0.0.3 (10.0.0.3) 56(84) bytes of data.
64 bytes from 10.0.0.3: icmp_seq=1 ttl=64 time=0.633 ms
64 bytes from 10.0.0.3: icmp_seq=2 ttl=64 time=0.074 ms
--- 10.0.0.3 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1002ms
rtt min/avg/max/mdev = 0.074/0.353/0.633/0.280 ms
```

4. pod 访问外网，因为 cni0 是一个内网地址，本身无法访问外网，eth0 通常会连接到一个访问外网的路由器上，需要开启 linux ip 转发和对 pod 访问外部网络的数据包做 ip 伪装，否则外部不知道回包

**pod 访问外网**:

```
root@vagrant:/home/vagrant# echo 1 > /proc/sys/net/ipv4/ip_forward
root@vagrant:/home/vagrant# iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
root@vagrant:/home/vagrant# ip netns exec ns1 ping baidu.com
PING baidu.com (39.156.69.79) 56(84) bytes of data.
64 bytes from 39.156.69.79: icmp_seq=1 ttl=61 time=39.8 ms
64 bytes from 39.156.69.79: icmp_seq=2 ttl=61 time=51.3 ms
--- baidu.com ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1002ms
rtt min/avg/max/mdev = 39.889/45.612/51.336/5.727 ms
```

## 跨主机 pod 网络
以上解决了同一个 host pod 的网络问题，还有两个问题没有解决
- pod 的 IP 地址分配
- 跨主机 pod 的网络互通

使用 vagrant 模拟场景，vagrant 默认启动的网络是 NAT 网络，NAT 网络的效果是虚拟机可以访问外部网络，外部无法访问内部，虚拟机之间的网络也是不通的。但是 NAT 网络是强制的，不然无法通过 vagrant ssh 到虚拟机。另外还有两种网络策略，private network 和 public network，private network 会为虚拟机创建一个私有网络，宿主机可以访问该网络，但是私有网络自身无法访问外部网络，还需要 nat 的网卡访问外部网络。还有一种是 public network，public network 和宿主机网络同级，也是从路由器中分配一个 ip，public network 的网卡可以直接访问外部网络，这边设置网络为 public network, 并设置 public network 为默认网关(use_dhcp_assigned_default_route: true)。

下面的 vagrantfile 会创建两台虚拟机，IP 和宿主机在同一个网段
```vagrantfile
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
	(1..2).each do |i|
		config.vm.define "node#{i}" do |node|
		# 设置虚拟机的Box
		config.vm.box = "bento/ubuntu-16.04"
		# 设置虚拟机的主机名
		node.vm.hostname="node#{i}"
		# 设置虚拟机的IP
      		node.vm.network "public_network",
         	# 设置为默认网关
			use_dhcp_assigned_default_route: true
		# 设置主机与虚拟机的共享目录
		config.vm.synced_folder "./", "/home/vagrant"
		# VirtaulBox相关配置
		node.vm.provider "virtualbox" do |v|
			# 设置虚拟机的名称
			v.name = "node#{i}"
			# 设置虚拟机的内存大小
			v.memory = 1024
			# 设置虚拟机的CPU个数
			v.cpus = 1
		end
	end
end
```

如下 eth0 是默认创建 nat 网卡，用于 vagrant ssh，eth1 是 public network 的网卡, IP 和宿主机一个网段。默认网关已经设置为 eth1
```bash
vagrant@node1:~$ ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 08:00:27:6b:c1:df brd ff:ff:ff:ff:ff:ff
    inet 10.0.2.15/24 brd 10.0.2.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::a00:27ff:fe6b:c1df/64 scope link
       valid_lft forever preferred_lft forever
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 08:00:27:99:1b:b6 brd ff:ff:ff:ff:ff:ff
    inet 10.104.34.233/22 brd 10.104.35.255 scope global eth1
       valid_lft forever preferred_lft forever
    inet6 fe80::a00:27ff:fe99:1bb6/64 scope link
       valid_lft forever preferred_lft forever
vagrant@node1:/home/vagrant# ip route
default via 10.104.35.254 dev eth1
```

因为 eth0 已经不是默认的网关，之前做 masquerade 的 iptables 规则也就无效了，修改为访问外部网络就做 masquerade, 这样 pod 又可以访问外网了
```bash
# 之前的规则
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# 之后的规则
iptables -t nat -A POSTROUTING -m addrtype ! --dst-type LOCAL -j MASQUERADE
```

**node2 -> node1 上的 pod**：

使用 vagrant 启动 node2，在 node2 上无法访问 node1 上的 pod，因为 node2 没有匹配的路由规则，会通过默认网关去转发，默认网关不知道 pod，所以访问失败。添加主机路由 `ip route add 10.0.0.0/24 via 10.104.34.23`，这条规则的作用是访问 `10.0.0.0/24` 网段的包都发送给主机 10.104.34.23，node1 知道如何访问 pod，并且 node1 和 node2 的网络是互通的，所以 ping 拿到了回包。
```bash
# 10.104.34.23 是 node1 eth1 的 IP 地址，这条路由规则的作用是访问 10.0.0.0/24 的网络都经过 10.104.34.23
root@node2:/home/vagrant# ip route add 10.0.0.0/24 via 10.104.34.23
root@node2:/home/vagrant# ping 10.0.0.3
PING 10.0.0.3 (10.0.0.3) 56(84) bytes of data.
64 bytes from 10.0.0.3: icmp_seq=1 ttl=63 time=0.414 ms
64 bytes from 10.0.0.3: icmp_seq=2 ttl=63 time=0.611 ms
64 bytes from 10.0.0.3: icmp_seq=3 ttl=63 time=0.869 ms
--- 10.0.0.3 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2002ms
rtt min/avg/max/mdev = 0.414/0.631/0.869/0.187 ms
```

**ip 地址分配如何保证不冲突**：

kubernetes 会为每个 node 分配一个 pod cidr，用于这个 node 上的 pod 的 IP 地址分配，controller manager 的启动参数 `--node-cidr-mask-size=26` 用于控制每个节点可用的子网大小，比如 cidr 为 26，那么该 node 可分配的 IP 为 64(2 的 6 次方) 个，`--cluster-cidr=10.224.0.0/17` 用于控制整个 k8s 集群的子网大小，2 的 15 次方为整个集群可用的 IP 数量 2 的 (26-17=9) 次方即该集群允许的最大 node 数量。

先手动为 node2 分配一个 pod cidr 10.0.1.0/24，运行一个 pod 网络, 测试跨节点 pod 的网络通信

**node2 的 pod <--> node1 的 pod**：

在 node2 上添加的 `ip route add 10.0.0.0/24 via 10.104.34.23` 让 node2 知道怎么去访问 node1 的 pod，但是 node1 上的 pod 无法访问 node2 上的 pod，同理在 node1 执行
`ip route add 10.0.1.0/24 via 10.104.34.139`, 如下网络可以互相访问。
```bash
root@node2:/home/vagrant# ip netns exec 1ce86ae37381585a ping 10.0.0.3
PING 10.0.0.3 (10.0.0.3) 56(84) bytes of data.
64 bytes from 10.0.0.3: icmp_seq=1 ttl=62 time=0.619 ms
64 bytes from 10.0.0.3: icmp_seq=2 ttl=62 time=0.538 ms
64 bytes from 10.0.0.3: icmp_seq=3 ttl=62 time=0.610 ms
root@node1:/home/vagrant# ip netns exec 39796a2f59e1720d ping 10.0.1.2
PING 10.0.1.2 (10.0.1.2) 56(84) bytes of data.
64 bytes from 10.0.1.2: icmp_seq=1 ttl=62 time=0.801 ms
64 bytes from 10.0.1.2: icmp_seq=2 ttl=62 time=0.540 ms
64 bytes from 10.0.1.2: icmp_seq=3 ttl=62 time=0.543 ms
```

```iptables -t nat -A POSTROUTING -m addrtype ! --dst-type LOCAL -j MASQUERADE``` 这条规则会导致所有的出口网络都会执行 NAT，k8s cni 的标准是 pod 和 pod 不需要执行 NAT 可以互相访问，如下可以看到pod 和 pod 互相访问的时候 pod 拿到的是 linux bridge 网桥的 IP。
```bash
root@node1:/home/vagrant# ip netns exec 39796a2f59e1720d tcpdump
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), capture size 262144 bytes
03:04:43.891227 IP 10.0.0.1 > 10.0.0.3: ICMP echo request, id 13701, seq 1, length 64
```

修改 iptables 让访问 pod cidr 的网段不执行 MASQUERADE, node1 和 node2 都执行如下
```bash
# 显示 nat 表下的 iptables 规则，并显示行号
root@node2:/home/vagrant# iptables -t nat -L --line-numbers
Chain PREROUTING (policy ACCEPT)
num  target     prot opt source               destination

Chain INPUT (policy ACCEPT)
num  target     prot opt source               destination

Chain OUTPUT (policy ACCEPT)
num  target     prot opt source               destination

Chain POSTROUTING (policy ACCEPT)
num  target     prot opt source               destination
1    MASQUERADE  all  --  anywhere             anywhere             ADDRTYPE match dst-type !LOCAL
# 删除 nat 表中 POSTROUTING 链中的规则 1
root@node2:/home/vagrant# iptables -t nat -D POSTROUTING 1
# 在 nat 表中新建链 masq
root@node2:/home/vagrant# iptables -t nat -N masq
# 访问 pod cidr 访问的网络不执行 MASQUERADE，其他网络默认执行 MASQUERADE
root@node2:/home/vagrant# iptables -t nat -A masq -d 10.0.0.0/24 -j RETURN
root@node2:/home/vagrant# iptables -t nat -A masq -d 10.0.1.0/24 -j RETURN
root@node2:/home/vagrant# iptables -t nat -A masq  -j MASQUERADE
root@node2:/home/vagrant# iptables -t nat -A POSTROUTING -m addrtype ! --dst-type LOCAL -j masq
```

再次从 node2 的 pod 去 ping node1 上的 pod，通过抓包可以看到已经可以拿到 pod 的 ip。
```bash
root@node1:/home/vagrant# ip netns exec 39796a2f59e1720d tcpdump
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), capture size 262144 bytes
03:36:04.872327 IP 10.0.1.2 > 10.0.0.3: ICMP echo request, id 13751, seq 1, length 64
```

## 使用 kind 验证 cni

kind 使用 docker 运行一个 k8s 集群，相比于 minikube 的优点是更加轻量，支持多 worker 节点，非常适合用于 cni 的测试。`kind create cluster --config=cluster.yaml --image=kindest/node:v1.16.3-jq` 创建一个 k8s 集群，通过 `disableDefaultCNI: true` 让 kind 不安装默认的 cni 插件。`--image=kindest/node:v1.16.3-jq` 指定了自己 build 的 nodeimage，因为 my-cni 命令的执行依赖 jq 命令，在 base 镜像上安装了 jq 命令(Dockerfile-kindnode)。

`--config` 指定 cluster 的配置文件，`--image` 自定义 k8s node 的镜像。
```bash
➜  cni-from-scratch git:(master) ✗ kind create cluster --config=cluster.yaml --image=kindest/node:v1.16.3-jq
```

```yaml
kind: Cluster
apiVersion: kind.sigs.k8s.io/v1alpha3
networking:
  disableDefaultCNI: true
kubeadmConfigPatches:
- |
  apiVersion: kubeadm.k8s.io/v1beta1
  kind: ClusterConfiguration
  metadata:
    name: config
nodes:
- role: control-plane
- role: worker
- role: worker
```

cni 的执行顺序如下：
1. init.sh 输出一份 cni 的配置文件到 cni-dir(通过 hostpath 挂载宿主机的 cni-config-dir)，拷贝 my-cni 脚本到 cni-bin-dir 下(同上，通过 hostpath)
2. init.sh 初始化 iptables 并添加主机路由
3. tail cni 执行的日志
4. kubelet 会在启动和销毁容器的时候读取 cni-config-dir 下的配置文件，根据 type 字段执行 mycni

部署 my-cni：
```bash
# 构建 mycni 容器，目前依赖 kubelet，因为需要获取 node IP 和 podcidir 的对应关系
docker build -t mycni/mycni:v0.1.0 .
# 导入 mycni 镜像
kind load docker-image mycni/mycni:v0.1.0
kubectl apply -f cni.yaml
```

**测试网络连通性**：

1. 如果 coredns 能成功运行，说明节点能访问 pod 网络，因为 coredns 有健康检查
2. 运行 `make test` 运行两个 pod，验证跨节点的 pod 网络通信和 pod 访问外网

```bash
➜  cni-from-scratch git:(master) ✗ kubectl get po -o wide
NAME                         READY   STATUS    RESTARTS   AGE   IP           NODE           NOMINATED NODE   READINESS GATES
tmp-31733-5d7494d5bb-rrkh9   1/1     Running   0          37m   10.244.2.4   kind-worker    <none>           <none>
tmp-32332-55c5cb6594-wpgdv   1/1     Running   0          39m   10.244.1.2   kind-worker2   <none>           <none>
➜  cni-from-scratch git:(master) ✗ kubectl exec -it tmp-31733-5d7494d5bb-rrkh9 ping 10.244.1.2
PING 10.244.1.2 (10.244.1.2) 56(84) bytes of data.
64 bytes from 10.244.1.2: icmp_seq=1 ttl=62 time=0.249 ms
64 bytes from 10.244.1.2: icmp_seq=2 ttl=62 time=0.186 ms
--- 10.244.1.2 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1024ms
rtt min/avg/max/mdev = 0.186/0.217/0.249/0.034 ms
➜  cni-from-scratch git:(master) ✗ kubectl exec -it tmp-31733-5d7494d5bb-rrkh9 ping baidu.com
PING baidu.com (220.181.38.148) 56(84) bytes of data.
64 bytes from 220.181.38.148: icmp_seq=1 ttl=36 time=32.0 ms
64 bytes from 220.181.38.148: icmp_seq=2 ttl=36 time=34.2 ms
--- baidu.com ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 32.049/33.169/34.289/1.120 ms
```
