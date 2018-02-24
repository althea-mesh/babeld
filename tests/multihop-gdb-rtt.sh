#!/usr/bin/env bash
set -eux

BABELPATH=${BABELPATH:=../babeld}
CONFIGPORT=${CONFIGPORT:=6126}
GDBPATH=${GDBPATH:=gdb}
LABPATH=${LABPATH:=./network-lab.sh}

# This is a basic integration test for the Althea fork of Babeld, it focuses on
# validating that instances actually come up and communicate

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root :("
   exit 1
fi

fail_string()
{
 if grep -q $1 "$2"; then
   echo "FAILED: $1 in $2"
   exit 1
 fi
}

pass_string()
{
 if ! grep -q $1 "$2"; then
   echo "FAILED: $1 not in $2"
   exit 1
 fi
}

cleanup()
{
 set +eux
  kill -9 $(cat babeld-n1.pid)
  kill -9 $(cat babeld-n2.pid)
  kill -9 $(cat babeld-n3.pid)
  rm -f babeld-n*
 set -eux
}

cleanup

 source $LABPATH << EOF
{
  "nodes": {
    "1": { "ip": "1.0.0.1" },
    "2": { "ip": "1.0.0.2" },
    "3": { "ip": "1.0.0.3" },
    "4": { "ip": "1.0.0.4" }
},
  "edges": [
     {
      "nodes": ["1", "2"],
      "->": "loss random 0%",
      "<-": "loss random 0%"
     },
     {
      "nodes": ["2", "3"],
      "->": "loss random 0%",
      "<-": "loss random 0%"
     },
     {
      "nodes": ["3", "4"],
      "->": "loss random 0%",
      "<-": "loss random 0%"
     },
     {
      "nodes": ["4", "1"],
      "->": "loss random 0%",
      "<-": "loss random 0%"
     }
  ]
}
EOF

cat << EOF
         ======== TOPOLOGY ========

     ,---- netlab-2 (price \$10) -----,
    /                                  \\
   /                                    \\
netlab-1 (price \$5)                 netlab-3 (price \$1)
   \\                                    /
    \\                                  /
     \`---- netlab-4 (price \$15) -----\`

EOF

ip netns exec netlab-1 sysctl -w net.ipv4.ip_forward=1
ip netns exec netlab-1 sysctl -w net.ipv6.conf.all.forwarding=1
ip netns exec netlab-1 ip link set up dev lo
ip netns exec netlab-1 $BABELPATH -G $CONFIGPORT -I babeld-n1.pid -d 3 -L babeld-n1.log -P 5 -w veth-1-2 veth-1-4 -C 'default max-rtt-penalty 100' -C 'default enable-timestamps true' &

ip netns exec netlab-2 sysctl -w net.ipv4.ip_forward=1
ip netns exec netlab-2 sysctl -w net.ipv6.conf.all.forwarding=1
ip netns exec netlab-2 ip link set up dev lo
ip netns exec netlab-2 $BABELPATH -G $CONFIGPORT -I babeld-n2.pid -d 3 -L babeld-n2.log -P 10 -w veth-2-1 veth-2-3 -C 'default max-rtt-penalty 100' -C 'default enable-timestamps true' &

ip netns exec netlab-3 sysctl -w net.ipv4.ip_forward=1
ip netns exec netlab-3 sysctl -w net.ipv6.conf.all.forwarding=1
ip netns exec netlab-3 ip link set up dev lo
ip netns exec netlab-3 $BABELPATH -G $CONFIGPORT -I babeld-n3.pid -d 3 -L babeld-n3.log -P 1 -w veth-3-2 veth-3-4 -C 'default max-rtt-penalty 100' -C 'default enable-timestamps true' &

ip netns exec netlab-4 sysctl -w net.ipv4.ip_forward=1
ip netns exec netlab-4 sysctl -w net.ipv6.conf.all.forwarding=1
ip netns exec netlab-4 ip link set up dev lo
ip netns exec netlab-4 $GDBPATH --args $BABELPATH -G $CONFIGPORT -I babeld-n4.pid -d 1 -L babeld-n4.log -P 15 -w veth-4-1 veth-4-3 'default max-rtt-penalty 100' -C 'default enable-timestamps true'

