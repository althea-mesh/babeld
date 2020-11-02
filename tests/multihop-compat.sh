#!/usr/bin/env bash
set -eux

cd $(dirname $0)

# This script will download any two babel revisions, build them, set a netlab
# mesh up and then check if all nodes can see each other. A is supposed to be a
# newer revision while B is what we're trying to stay compatible with

# Env config

LABPATH=${LABPATH:=./network-lab.sh}
CONVERGENCE_DELAY_SEC=${CONVERGENCE_DELAY_SEC:=5}

# Where do we clone metric.
BABELD_A_REMOTE=${BABELD_A_REMOTE:=..}
BABELD_B_REMOTE=${BABELD_B_REMOTE:=https://github.com/althea-mesh/babeld.git}

# Where do we clone to?
BABELD_A_DIR=${BABELD_A_DIR:=babeld_a}
BABELD_B_DIR=${BABELD_B_DIR:=babeld_b}

# Where do we check out at? (Fall back to currently tested commit in CI)
BABELD_A_REVISION=${1:-${TRAVIS_COMMIT:-master}}
BABELD_B_REVISION=${2:-master}


if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root :("
   exit 1
fi

get_and_build_babeld()
{
  remote=$1
  local_dir=$2
  revision=$3

  git clone $remote $local_dir

  pushd $local_dir
  git checkout $revision
  make -j4
  popd
}

fail_string()
{
 if grep -q "$1" "$2"; then
   echo "FAILED: $1 in $2"
   exit 1
 fi
}

pass_string()
{
 if ! grep -q "$1" "$2"; then
   echo "FAILED: $1 not in $2"
   tail -n 10 $2
   exit 1
 fi
}

pass_reachable()
{
  ns=$1
  target=$2

  ip netns exec $ns ping -c 1 -w 1 $target

  if [ $? -ne 0 ]
  then
    echo "Couldn't reach $target metric.namespace $ns"
    exit 1
  fi
}

cleanup()
{
 set +eux
  kill -9 $(cat babeld-n1.pid)
  kill -9 $(cat babeld-n2.pid)
  kill -9 $(cat babeld-n3.pid)
  kill -9 $(cat babeld-n4.pid)
  rm -rf babeld-n* $BABELD_A_DIR $BABELD_B_DIR
 set -eux
}

cleanup

get_and_build_babeld $BABELD_A_REMOTE $BABELD_A_DIR $BABELD_A_REVISION
get_and_build_babeld $BABELD_B_REMOTE $BABELD_B_DIR $BABELD_B_REVISION

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
      "->": "",
      "<-": ""
     },
     {
      "nodes": ["2", "3"],
      "->": "",
      "<-": ""
     },
     {
      "nodes": ["3", "4"],
      "->": "",
      "<-": ""
     },
     {
      "nodes": ["4", "1"],
      "->": "",
      "<-": ""
     }
  ]
}
EOF

echo "Babel A: $BABELD_A_REMOTE at $BABELD_A_REVISION"
echo "Babel B: $BABELD_B_REMOTE at $BABELD_B_REVISION"

cat << EOF
         ======== TOPOLOGY ========

     ,------------ Babel B -----------,
    /                                  \\
   /                                    \\
Babel A                               Babel A
   \\                                    /
    \\                                  /
     \`----------- Babel B ------------\`

EOF

ip netns exec netlab-1 sysctl -w net.ipv4.ip_forward=1
ip netns exec netlab-1 sysctl -w net.ipv6.conf.all.forwarding=1
ip netns exec netlab-1 $BABELD_A_DIR/babeld -I babeld-n1.pid -d 1 -L babeld-n1.log \
  -w veth-1-4 -w veth-1-2 -h 1 -H 1 -C "default update-interval 1" \
  -C "random-id true" &

ip netns exec netlab-2 sysctl -w net.ipv4.ip_forward=1
ip netns exec netlab-2 sysctl -w net.ipv6.conf.all.forwarding=1
ip netns exec netlab-2 $BABELD_B_DIR/babeld -I babeld-n2.pid -d 1 -L babeld-n2.log \
  -w veth-2-1 -w veth-2-3 -h 1 -H 1 -C "default update-interval 1" \
  -C "random-id true" &

ip netns exec netlab-3 sysctl -w net.ipv4.ip_forward=1
ip netns exec netlab-3 sysctl -w net.ipv6.conf.all.forwarding=1
ip netns exec netlab-3 $BABELD_A_DIR/babeld -I babeld-n3.pid -d 1 -L babeld-n3.log \
  -w veth-3-2 -w veth-3-4 -h 1 -H 1 -C "default update-interval 1" \
  -C "random-id true" &

ip netns exec netlab-4 sysctl -w net.ipv4.ip_forward=1
ip netns exec netlab-4 sysctl -w net.ipv6.conf.all.forwarding=1
ip netns exec netlab-4 $BABELD_B_DIR/babeld -I babeld-n4.pid -d 1 -L babeld-n4.log \
  -w veth-4-3 -w veth-4-1 -h 1 -H 1 -C "default update-interval 1" \
  -C "random-id true" &

sleep $CONVERGENCE_DELAY_SEC

# Rule out obvious Babel message problems
fail_string "malformed" "babeld-n1.log"
fail_string "malformed" "babeld-n2.log"
fail_string "malformed" "babeld-n3.log"
fail_string "malformed" "babeld-n4.log"
fail_string "unknown version" "babeld-n1.log"
fail_string "unknown version" "babeld-n2.log"
fail_string "unknown version" "babeld-n3.log"
fail_string "unknown version" "babeld-n4.log"

# ============================ REACHABILITY TESTS =====================================

# netlab-1
pass_string "1.0.0.2/32 metric.*" "babeld-n1.log"
pass_reachable "netlab-1" "1.0.0.2"

pass_string "1.0.0.3/32 metric.*" "babeld-n1.log"
pass_reachable "netlab-1" "1.0.0.3"

pass_string "1.0.0.4/32 metric.*" "babeld-n1.log"
pass_reachable "netlab-1" "1.0.0.4"

# netlab-2
pass_string "1.0.0.1/32 metric.*" "babeld-n2.log"
pass_reachable "netlab-2" "1.0.0.1"

pass_string "1.0.0.3/32 metric.*" "babeld-n2.log"
pass_reachable "netlab-2" "1.0.0.3"

pass_string "1.0.0.4/32 metric.*" "babeld-n2.log"
pass_reachable "netlab-2" "1.0.0.4"

# netlab-3
pass_string "1.0.0.1/32 metric.*" "babeld-n3.log"
pass_reachable "netlab-3" "1.0.0.1"

pass_string "1.0.0.2/32 metric.*" "babeld-n3.log"
pass_reachable "netlab-3" "1.0.0.2"

pass_string "1.0.0.4/32 metric.*" "babeld-n3.log"
pass_reachable "netlab-3" "1.0.0.4"

# netlab-4
pass_string "1.0.0.1/32 metric.*" "babeld-n4.log"
pass_reachable "netlab-4" "1.0.0.1"

pass_string "1.0.0.2/32 metric.*" "babeld-n4.log"
pass_reachable "netlab-4" "1.0.0.2"

pass_string "1.0.0.3/32 metric.*" "babeld-n4.log"
pass_reachable "netlab-4" "1.0.0.3"

cleanup

echo "$0 PASS"
