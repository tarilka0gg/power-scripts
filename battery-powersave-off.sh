#!/bin/sh
# AC restored: bring the P-core threads (cpu0-15) back online, performance
# everywhere, and restart the dGPU users stopped by battery-powersave-on.sh.

U=tarilka0gg
UENV="XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1"
NOCTALIA_CONF=/home/$U/.config/noctalia/config.toml

for n in $(seq 0 15); do
    echo 1 > "/sys/devices/system/cpu/cpu$n/online" 2>/dev/null
done

for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$g" ] && echo performance > "$g" 2>/dev/null
done

for e in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$e" ] && echo performance > "$e" 2>/dev/null
done

# Online CPUs come back with C3 enabled - re-disable on all, as performance.start does.
for f in /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do
    echo 1 > "$f" 2>/dev/null
done

# Direct sysfs write re-arms the EC limits even if PPD already says performance.
powerprofilesctl set performance 2>/dev/null
echo performance > /sys/firmware/acpi/platform_profile 2>/dev/null

CONF=/etc/conf.d/sustained-turbo
if [ -f "$CONF.bak-battery" ]; then
    mv "$CONF.bak-battery" "$CONF"
    rc-service sustained-turbo restart >/dev/null 2>&1
fi

rc-service nvidia-powerd start >/dev/null 2>&1

if [ -f "$NOCTALIA_CONF" ]; then
    su $U -c "sed -i 's/^gpu_poll_seconds *= *[0-9.]*/gpu_poll_seconds = 5.0/' '$NOCTALIA_CONF'"
    su $U -c "$UENV noctalia msg config-reload" >/dev/null 2>&1
fi

NIRI_SOCK=$(find /run/user/1000 -maxdepth 1 -name "niri.wayland-*.sock" 2>/dev/null | head -1)
if [ -n "$NIRI_SOCK" ]; then
    su $U -c "NIRI_SOCKET='$NIRI_SOCK' niri msg output eDP-1 mode '2560x1440@165'" >/dev/null 2>&1
    pgrep -x sunshine >/dev/null || su $U -c "NIRI_SOCKET='$NIRI_SOCK' niri msg action spawn -- sunshine" >/dev/null 2>&1
fi

# throttled applies UNDERVOLT.{AC,BATTERY} only at start/resume, not on a
# live AC change (only PL limits follow) - restart so the right offset lands.
rc-service throttled restart >/dev/null 2>&1
