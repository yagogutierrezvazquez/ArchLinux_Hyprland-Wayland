#!/bin/sh
# System stats for the Quickshell dashboard, one "key=value" per line.
#   perf-stats.sh        one sample (counters; the dashboard turns them into rates)
#   perf-stats.sh info   static names: CPU model, GPU name, root disk
# Read-only: everything comes from /proc and /sys, so no root and no perf
# counters are needed (intel_gpu_top would need CAP_PERFMON).

# r <path (glob ok)> <key>: first line of the first matching file, empty if missing
r() { v=$(cat $1 2>/dev/null | head -n1); echo "$2=$v"; }

if [ "$1" = info ]; then
    echo "cpuModel=$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -n1)"
    echo "gpuName=$(lspci -mm -d ::0300 2>/dev/null | head -n1 | cut -d'"' -f4,6 | tr '"' ' ')"
    echo "disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null | head -n1)"
    exit 0
fi

echo "cpu=$(head -n1 /proc/stat | cut -d' ' -f2-)"
awk '/^MemTotal:/ { print "memTotal=" $2 } /^MemAvailable:/ { print "memAvail=" $2 }' /proc/meminfo
r '/sys/devices/platform/coretemp.0/hwmon/hwmon*/temp1_input' temp
awk '/^cpu MHz/ { s += $4; n++ } END { if (n) printf "cpuMhz=%d\n", s / n }' /proc/cpuinfo
r /proc/uptime uptime
r /proc/sys/kernel/hostname host

# Intel GPU (i915): RC6 residency = ms the GPU spent idle/powered down
r '/sys/class/drm/card*/gt/gt0/rc6_residency_ms' rc6
r '/sys/class/drm/card*/gt_act_freq_mhz' gpuMhz
r '/sys/class/drm/card*/gt_RP0_freq_mhz' gpuMaxMhz

# Network: interface of the default route (byte counters since boot)
dev=$(ip route show default 2>/dev/null | awk '{ print $5; exit }')
echo "netDev=$dev"
if [ -n "$dev" ]; then
    r "/sys/class/net/$dev/statistics/rx_bytes" rx
    r "/sys/class/net/$dev/statistics/tx_bytes" tx
fi

# Root filesystem (KiB) and NVMe temperature
df -kP / | awk 'NR == 2 { print "diskTotal=" $2; print "diskUsed=" $3 }'
for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name")" = nvme ] && r "$h/temp1_input" diskTemp && break
done
