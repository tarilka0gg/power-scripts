#!/bin/sh
# Restore full performance: bring every CPU back online, reset governor,
# balanced platform profile, normal undervolt, fan curve, and monitors.

for c in /sys/devices/system/cpu/cpu[0-9]*; do
    echo 1 > "$c/online" 2>/dev/null
done

for c in /sys/devices/system/cpu/cpu*/cpufreq; do
    [ -d "$c" ] || continue
    maxfreq=$(cat "$c/cpuinfo_max_freq" 2>/dev/null)
    [ -n "$maxfreq" ] && echo "$maxfreq" > "$c/scaling_max_freq" 2>/dev/null
    echo performance > "$c/scaling_governor" 2>/dev/null
    echo performance > "$c/energy_performance_preference" 2>/dev/null
done

# C3 back off on every core (as performance.start does; onlined CPUs come
# back with it enabled).
for f in /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do
    echo 1 > "$f" 2>/dev/null
done

# dGPU pollers back (see idle-on.sh step 9).
rm -f /run/deep-idle
rc-service nvidia-powerd start >/dev/null 2>&1
NCONF=/home/tarilka0gg/.config/noctalia/config.toml
[ -f "$NCONF" ] && su tarilka0gg -c "sed -i 's/^gpu_poll_seconds *= *[0-9.]*/gpu_poll_seconds = 5.0/' '$NCONF' && XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 noctalia msg config-reload" >/dev/null 2>&1

echo balanced > /sys/firmware/acpi/platform_profile 2>/dev/null

# Restore LOAD_W in the fan curve if idle-on.sh had zeroed it.
CONF=/etc/conf.d/sustained-turbo
if [ -f "$CONF.bak-preidle" ]; then
    mv "$CONF.bak-preidle" "$CONF"
    rc-service sustained-turbo restart >/dev/null 2>&1
fi

# Restore normal undervolt (throttled.conf is the live daemon — see idle-on.sh).
TCONF=/etc/throttled.conf
if [ -f "$TCONF.bak-preidle" ]; then
    mv "$TCONF.bak-preidle" "$TCONF"
    rc-service throttled restart >/dev/null 2>&1
fi

# Reauthorize USB devices.
for d in 1-14 1-2.3 1-3 1-6; do
    [ -e "/sys/bus/usb/devices/$d/authorized" ] && echo 1 > "/sys/bus/usb/devices/$d/authorized" 2>/dev/null
done

# Swap USB-C port back to sourcing power.
echo source > /sys/class/typec/port0/power_role 2>/dev/null

# Restore internal backlight.
BL=/sys/class/backlight/intel_backlight
if [ -f /run/idle-backlight.bak ]; then
    cat /run/idle-backlight.bak > "$BL/brightness" 2>/dev/null
    rm -f /run/idle-backlight.bak
else
    cat "$BL/max_brightness" > "$BL/brightness" 2>/dev/null
fi

# TEMPORARILY DISABLED (2026-09-21) — see matching note in idle-on.sh.
# ddcutil setvcp d6 1 --display 1 >/dev/null 2>&1

# Power the monitor(s) back on (niri-side, in case anything else changed it).
su tarilka0gg -c 'XDG_RUNTIME_DIR=/run/user/1000 niri msg action power-on-monitors' >/dev/null 2>&1

# Leaving idle while unplugged: hand over to battery mode instead of full perf.
[ "$(cat /sys/class/power_supply/ACAD/online 2>/dev/null)" = "0" ] && /usr/local/bin/battery-powersave-on.sh >/dev/null 2>&1

echo "Deep idle OFF. Online CPUs: $(cat /sys/devices/system/cpu/online)"
