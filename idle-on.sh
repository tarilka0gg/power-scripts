#!/bin/sh
# Deep-idle mode: keep the machine fully running (SSH/network always up,
# no suspend/WoL involved at all) but minimize power draw as much as
# possible without actually sleeping. No screen needed while in this mode.

# 1) Offline every logical CPU except cpu0 (cpu0 can't be offlined anyway —
#    this kernel build has no online toggle for it at all, confirmed via
#    direct test — so it's the one that stays on by necessity either way).
for c in /sys/devices/system/cpu/cpu[0-9]*; do
    n=$(basename "$c" | tr -d 'cpu')
    [ "$n" = "0" ] && continue
    echo 0 > "$c/online" 2>/dev/null
done

# 2) Force powersave governor + lowest available frequency on cpu0.
echo powersave > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
minfreq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq 2>/dev/null)
[ -n "$minfreq" ] && echo "$minfreq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null
#    On intel_pstate/HWP the governor label barely matters - EPP drives it
#    (2026-09-28: powersave+EPP=performance still boosted E-cores to 3.7GHz).
echo power > /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null

# 2b) Re-enable C3 (performance.start disables it against game input stutter);
#     without it the package can't go below PC2/PC3.
echo 0 > /sys/devices/system/cpu/cpu0/cpuidle/state3/disable 2>/dev/null

# 3) ACPI power-saver platform profile.
echo low-power > /sys/firmware/acpi/platform_profile 2>/dev/null

# 4) Fans off at true idle via the auto curve, PWM_FLOOR=0 (NOT MODE=fixed
#    — 2026-09-21 finding: a fixed pwm that ignores real temp/power fights
#    the EC's own safety floor and causes periodic ~4s RPM spikes. A curve
#    value that tracks real conditions never triggers that fight — at
#    genuine idle temp/power the curve computes 0 on its own, cleanly.
CONF=/etc/conf.d/sustained-turbo
CONF_IDLE=/etc/conf.d/sustained-turbo-idle.conf
if [ ! -f "$CONF.bak-preidle" ] && [ -f "$CONF_IDLE" ]; then
    cp "$CONF" "$CONF.bak-preidle"
    cp "$CONF_IDLE" "$CONF"
    rc-service sustained-turbo restart >/dev/null 2>&1
fi

# 5) Deeper CPU undervolt (-200mV instead of the usual ~-140/-150) — safe
#    headroom at these idle clocks that wouldn't hold under full turbo.
#    2026-09-25 finding: intel-undervolt is NOT the live daemon — throttled
#    reapplies its own CORE value every second and wins the race, so editing
#    intel-undervolt.conf alone was a no-op. Edit throttled.conf's AC section
#    instead (this machine runs on AC while idle-scripted).
TCONF=/etc/throttled.conf
if [ ! -f "$TCONF.bak-preidle" ]; then
    cp "$TCONF" "$TCONF.bak-preidle"
    python3 -c "
import re
path = '$TCONF'
with open(path) as f:
    c = f.read()
c = re.sub(r'(\[UNDERVOLT\.AC\][^\[]*?CORE: )-?\d+', r'\g<1>-200', c, count=1)
with open(path, 'w') as f:
    f.write(c)
"
    rc-service throttled restart >/dev/null 2>&1
fi

# 6) Deauthorize every USB device except the keyboard (1-2.4). Leaves
#    the parent hubs (1-2, 2-2) and root controllers alone.
for d in 1-14 1-2.3 1-3 1-6; do
    [ -e "/sys/bus/usb/devices/$d/authorized" ] && echo 0 > "/sys/bus/usb/devices/$d/authorized" 2>/dev/null
done

# 7) USB-C port feeding the external monitor is currently sourcing
#    power out (power_role: source). Try a role swap to stop that —
#    this is EC/PD-negotiated, less predictable than plain USB devices;
#    a failed/rejected swap is harmless (port just stays as-is).
echo sink > /sys/class/typec/port0/power_role 2>/dev/null

# 8) TEMPORARILY DISABLED (2026-09-21) — suspect ddcutil's I2C/DDC call to
#    the external monitor as a possible contributor to the last hang.
#    Re-enable once isolated from the undervolt/CPU-offline changes as
#    the actual cause.
# BL=/sys/class/backlight/intel_backlight
# if [ -d "$BL" ]; then
#     cat "$BL/brightness" > /run/idle-backlight.bak 2>/dev/null
#     echo 0 > "$BL/brightness" 2>/dev/null
# fi
# ddcutil setvcp d6 4 --display 1 >/dev/null 2>&1

# 9) Let the dGPU reach D3cold: every NVML query wakes it (2026-09-28).
#    /run/deep-idle makes sustained-turbo skip nvidia-smi; sunshine is left
#    running on purpose (remote access while headless).
touch /run/deep-idle
rc-service nvidia-powerd stop >/dev/null 2>&1
NCONF=/home/tarilka0gg/.config/noctalia/config.toml
[ -f "$NCONF" ] && su tarilka0gg -c "sed -i 's/^gpu_poll_seconds *= *[0-9.]*/gpu_poll_seconds = 86400.0/' '$NCONF' && XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 noctalia msg config-reload" >/dev/null 2>&1

# 10) Screen off via niri DPMS (not ddcutil/DDC - see step 8). The panel has
#     no PSR, so with it lit the package can't leave PC2/PC3 (~9W). Any
#     input turns it back on.
NS=$(find /run/user/1000 -maxdepth 1 -name "niri.wayland-*.sock" 2>/dev/null | head -1)
[ -n "$NS" ] && su tarilka0gg -c "NIRI_SOCKET='$NS' niri msg action power-off-monitors" >/dev/null 2>&1

echo "Deep idle ON. Online CPUs: $(cat /sys/devices/system/cpu/online)"
