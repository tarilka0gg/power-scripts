#!/bin/sh
# Battery mode: offline the P-core threads (cpu0-15, 8 P-cores x2 HT),
# leave the 8 E-cores (cpu16-23) running, powersave everywhere still online,
# and stop everything that keeps waking the dGPU so it can reach D3cold.

U=tarilka0gg
UENV="XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1"
NOCTALIA_CONF=/home/$U/.config/noctalia/config.toml

for n in $(seq 0 15); do
    echo 0 > "/sys/devices/system/cpu/cpu$n/online" 2>/dev/null
done

for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$g" ] && echo powersave > "$g" 2>/dev/null
done

# On intel_pstate/HWP, the governor label alone barely matters - EPP is
# what actually drives frequency/turbo behavior.
for e in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$e" ] && echo power > "$e" 2>/dev/null
done

# Re-enable C3 (performance.start disables it against input stutter in games):
# without it the package never reaches deep package C-states (~9W uncore idle).
for f in /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do
    echo 0 > "$f" 2>/dev/null
done

# Passive cooling: idle fan curve (PWM_FLOOR=0, curve starts at 60C). Own
# backup name so it doesn't collide with idle-on.sh's .bak-preidle.
CONF=/etc/conf.d/sustained-turbo
if [ ! -f "$CONF.bak-battery" ] && [ ! -f "$CONF.bak-preidle" ] && [ -f "$CONF-idle.conf" ]; then
    cp "$CONF" "$CONF.bak-battery"
    cp "$CONF-idle.conf" "$CONF"
    rc-service sustained-turbo restart >/dev/null 2>&1
fi

powerprofilesctl set power-saver 2>/dev/null
echo low-power > /sys/firmware/acpi/platform_profile 2>/dev/null

# dGPU pollers: each NVML query pulls the GPU out of D3cold (~20W+ at the
# battery). Confirmed 2026-09-28: with these gone it drops to D3cold.
rc-service nvidia-powerd stop >/dev/null 2>&1
pkill -x sunshine
if [ -f "$NOCTALIA_CONF" ]; then
    su $U -c "sed -i 's/^gpu_poll_seconds *= *[0-9.]*/gpu_poll_seconds = 86400.0/' '$NOCTALIA_CONF'"
    su $U -c "$UENV noctalia msg config-reload" >/dev/null 2>&1
fi

# Drop the panel to 60Hz (from 165Hz).
NIRI_SOCK=$(find /run/user/1000 -maxdepth 1 -name "niri.wayland-*.sock" 2>/dev/null | head -1)
if [ -n "$NIRI_SOCK" ]; then
    su $U -c "NIRI_SOCKET='$NIRI_SOCK' niri msg output eDP-1 mode '2560x1440@60'" >/dev/null 2>&1
fi

# throttled applies UNDERVOLT.{AC,BATTERY} only at start/resume, not on a
# live AC change (only PL limits follow) - restart so the right offset lands.
rc-service throttled restart >/dev/null 2>&1
