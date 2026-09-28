# power-scripts

Deep-idle power management for a Linux laptop (HP Victus 16, i7-14650HX + RTX 4070,
OpenRC, `throttled`/intel-undervolt, `sustained-turbo` fan daemon, niri Wayland compositor).

`idle-on.sh` puts the machine into a deep-idle mode that stays fully up (SSH/network
alive, no suspend) while minimizing power draw: offlines all but cpu0, forces the
lowest CPU frequency and powersave EPP, drops to a deeper undervolt, deauthorizes
non-essential USB devices, lets the dGPU reach D3cold, and powers off the display via
niri DPMS. `idle-off.sh` reverses all of it. `idle-measure.sh` is a 60-second sampler
for package power, iGPU RC6 residency, PC6/PC8/PC10 package C-state residency, dGPU
power state, and battery draw, used to validate idle changes.

`sustained-turbo-idle.conf` is the fan-curve override applied while idle: floors the
PWM curve to true 0 RPM at low load/temp instead of the normal fan-always-spinning-a-bit
floor, without touching the rest of the curve.

Must run as root (writes to `/sys`, restarts OpenRC services). Paths to
`/etc/conf.d/sustained-turbo`, `/etc/throttled.conf`, and the desktop user's
`noctalia` config are hardcoded for this specific machine — adapt before reuse
elsewhere.
