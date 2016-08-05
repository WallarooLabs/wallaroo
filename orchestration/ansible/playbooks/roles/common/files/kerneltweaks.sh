#!/bin/bash
set -euox pipefail

# kernel tweaks
# misc
echo tsc > /sys/devices/system/clocksource/clocksource0/current_clocksource # change clocksource
echo never > /sys/kernel/mm/transparent_hugepage/enabled # disable transparent hugepages
echo 1000000000 > /proc/sys/vm/nr_overcommit_hugepages # enable hugepages
sysctl -w vm.min_free_kbytes=8000000   # keep memory in reserve for when processes request it
sysctl -w vm.swappiness=0                       # change swappiness
sysctl -w vm.zone_reclaim_mode=0                       # disable zone reclaim on numa nodes
sysctl -w kernel.sched_migration_cost_ns=5000000
sysctl -w kernel.sched_autogroup_enabled=0
sysctl -w kernel.sched_latency_ns=36000000
sysctl -w kernel.sched_min_granularity_ns=10000000

# networking stuff
sysctl -w net.core.somaxconn=2048
sysctl -w net.core.netdev_max_backlog=30000
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
sysctl -w net.ipv4.tcp_wmem='4096 12582912 16777216'
sysctl -w net.ipv4.tcp_rmem='4096 12582912 16777216'
sysctl -w net.ipv4.tcp_max_syn_backlog=8096
sysctl -w net.ipv4.tcp_slow_start_after_idle=0
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.ip_local_port_range='10240 65535'
sysctl -w net.ipv4.tcp_abort_on_overflow=1    # maybe
sysctl -w net.ipv4.tcp_mtu_probing=1
sysctl -w net.ipv4.tcp_timestamps=1
sysctl -w net.ipv4.tcp_low_latency=1
sysctl -w net.core.default_qdisc=fq_codel
sysctl -w net.ipv4.tcp_window_scaling=1
sysctl -w net.ipv4.tcp_max_tw_buckets=7200000
sysctl -w net.ipv4.tcp_sack=0
sysctl -w net.ipv4.tcp_fin_timeout=15
sysctl -w net.ipv4.tcp_moderate_rcvbuf=1
sysctl -w net.core.rps_sock_flow_entries=65536
if [ -a /sys/class/net/eth0/queues/rx-0/rps_flow_cnt ]; then
  echo 32768 > /sys/class/net/eth0/queues/rx-0/rps_flow_cnt
  echo FFFFFFFF > /sys/class/net/eth0/queues/rx-0/rps_cpus
fi

if [ -a /sys/class/net/eth0/queues/rx-1/rps_flow_cnt ]; then
  echo 32768 > /sys/class/net/eth0/queues/rx-1/rps_flow_cnt
  echo FFFFFFFF > /sys/class/net/eth0/queues/rx-1/rps_cpus
fi

if [ -a /sys/class/net/eth0/queues/tx-0/xps_cpus ]; then
  echo FFFFFFFF > /sys/class/net/eth0/queues/tx-0/xps_cpus
fi

if [ -a /sys/class/net/eth0/queues/tx-1/xps_cpus ]; then
  echo FFFFFFFF > /sys/class/net/eth0/queues/tx-1/xps_cpus
fi

sysctl -w net.ipv4.tcp_fastopen=3

sysctl -w net.core.busy_poll=50 # spend cpu for lower latency
sysctl -w net.core.busy_read=50 # spend cpu for lower latency

##ethtool based tweaks
#ethtool -G eth0 rx 4096 tx 4096 || true # for to always succeed because if value is correct already it fails
#ethtool -K eth0 gso off
#ethtool -K eth0 gro off
#ethtool -K eth0 tso off
#ethtool -C eth0 rx-usecs 100 || true # for to always succeed because if value is correct already it fails


# filesystem stuff
sysctl -w vm.dirty_ratio=80                     # from 40
sysctl -w vm.dirty_bytes=2147483648                     # from 0
sysctl -w vm.dirty_background_bytes=268435456                     # from 0
sysctl -w vm.dirty_background_ratio=5           # from 10
sysctl -w vm.dirty_expire_centisecs=12000       # from 3000

for drive_path in /dev/xvd[a-z]
do
  drive=`basename ${drive_path}`
  if [ -b "${drive_path}" ]; then
    echo 2 > /sys/block/${drive}/queue/rq_affinity
    echo noop > /sys/block/${drive}/queue/scheduler
    if [ `cat /sys/block/${drive}/device/modalias` != xen:vbd ]; then
      echo 256 > /sys/block/${drive}/queue/nr_requests
    fi
    echo 256 > /sys/block/${drive}/queue/read_ahead_kb
    echo 0 > /sys/block/${drive}/queue/add_random
    echo 0 > /sys/block/${drive}/queue/rotational
  fi
done

# apply changes
sysctl -p # apply changed settings

# from: https://www.ibm.com/developerworks/community/wikis/home?lang=en#!/wiki/W51a7ffcf4dfd_4b40_9d82_446ebc23c550/page/Linux%20on%20Power%20-%20Low%20Latency%20Tuning
# Make sure to set the realtime bandwidth reservation to zero, or even real-time tasks will be asks to step aside for a bit
echo 0 > /proc/sys/kernel/sched_rt_runtime_us

# If a soft limit is set for the maximum realtime priority which is less than the hard limit and needs to be raised, the "ulimit -r" command can do so
ulimit -r 90

