#!/bin/bash
sleep 30
R=/sys/class/powercap/intel-rapl:0
rd(){ rdmsr -p16 -u $1 2>/dev/null || echo 0; }
a1=$(cat $R/energy_uj); r1=$(cat /sys/class/drm/card1/power/rc6_residency_ms)
t1=$(rd 0x10); p6a=$(rd 0x3F9); p8a=$(rd 0x630); p10a=$(rd 0x632)
sleep 30
a2=$(cat $R/energy_uj); r2=$(cat /sys/class/drm/card1/power/rc6_residency_ms)
t2=$(rd 0x10); p6b=$(rd 0x3F9); p8b=$(rd 0x630); p10b=$(rd 0x632)
dt=$((t2-t1))
awk -v e=$((a2-a1)) 'BEGIN{printf "package: %.1f W\n", e/30e6}'
echo "iGPU RC6: $(( (r2-r1)*100/30000 ))%"
awk -v a=$((p6b-p6a)) -v b=$((p8b-p8a)) -v c=$((p10b-p10a)) -v t=$dt 'BEGIN{printf "PC6 %.1f%%  PC8 %.1f%%  PC10 %.1f%%\n", 100*a/t, 100*b/t, 100*c/t}'
echo "dGPU: $(cat /sys/bus/pci/devices/0000:01:00.0/power_state)"
echo "battery: $(awk '{print $1/1e6}' /sys/class/power_supply/BAT1/power_now) W"
