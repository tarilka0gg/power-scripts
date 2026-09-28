# power-scripts

Power management for a Linux laptop (HP Victus 16, i7-14650HX + RTX 4070, OpenRC,
`throttled`/intel-undervolt, niri Wayland compositor). Three related but independent
pieces: a deep-idle mode you toggle manually, a fan/turbo daemon that runs all the
time, and an AC/battery mode switch that reacts to the charger.

## Deep idle (manual)

`idle-on.sh` puts the machine into a deep-idle mode that stays fully up (SSH/network
alive, no suspend) while minimizing power draw: offlines all but cpu0, forces the
lowest CPU frequency and powersave EPP, drops to a deeper undervolt, deauthorizes
non-essential USB devices, lets the dGPU reach D3cold, and powers off the display via
niri DPMS. `idle-off.sh` reverses all of it. `idle-measure.sh` is a 60-second sampler
for package power, iGPU RC6 residency, PC6/PC8/PC10 package C-state residency, dGPU
power state, and battery draw, used to validate idle changes.

## sustained-turbo (fan + turbo daemon)

The EC only grants full PL1 (80W) turbo for ~2-2.5 minutes before silently dropping
to the guaranteed clock — not a RAPL limit, the only working lever is re-arming
`/sys/firmware/acpi/platform_profile`. `sustained-turbo` is the daemon that does
this periodically (`auto`: only once load is genuinely sustained; `always`; `fixed`
for a constant fan PWM; `off`). Re-arming also forces the EC into a "user-defined
fan state" where its own auto fan curve stops working at all, so the daemon takes
over fan control itself for as long as it's rearming: a temp+load curve, plus a
package-power curve (RAPL + `nvidia-smi`) with hysteresis so it can ramp fans up
ahead of a temperature rise and back down once draw actually drops.

- `sustained-turbo` — the daemon itself (`/usr/local/bin/sustained-turbo`)
- `sustained-turbo.initd` — OpenRC service (`/etc/init.d/sustained-turbo`,
  `supervise-daemon`-managed, restarts it if it dies)
- `sustained-turbo.conf` — normal-operation config (`/etc/conf.d/sustained-turbo`):
  mode, thresholds, the temp/load and power fan curves
- `sustained-turbo-idle.conf` — fan-curve override applied while `idle-on.sh` is
  active: floors the PWM curve to true 0 RPM at low load/temp instead of the normal
  always-spinning-a-bit floor, without touching the rest of the curve

`rc-update add sustained-turbo default` to enable it; `rc-service sustained-turbo
restart` after editing `sustained-turbo.conf`.

## AC/battery switch

`battery-powersave-on.sh` / `-off.sh` swap the machine between two whole-system
profiles: on battery, offline the P-core hyperthreads, drop EPP to `power`, hand the
fan curve to the idle config, stop everything that polls the dGPU so it can reach
D3cold (`nvidia-powerd`, `sunshine`, Noctalia's GPU stat poller), and drop the panel
to 60Hz; on AC, reverse all of it and restore 165Hz + turbo. `battery-powersave.udev`
fires them on every AC plug/unplug (`ACAD` `power_supply` state change);
`zy-battery.start` applies the matching mode once at boot, since udev only fires on
*changes*. This runs after `performance.start` in `/etc/local.d`'s lexical ordering,
which would otherwise leave the machine in the performance state even on a
battery-only boot.

## Boot / resume re-arm

`performance.start` (`/etc/local.d/performance.start`, runs at boot) and
`90-power-limits-rearm` (`/usr/lib/elogind/system-sleep/90-power-limits-rearm`, runs
on resume) both do the same underlying fix for the same reason `sustained-turbo`
exists: writing "performance" into `platform_profile` — not just calling
`powerprofilesctl`, which is a no-op and leaves the EC's own limit in place if the
profile is already nominally "performance" — is what actually makes the EC honor
`throttled`'s PL1/PL2 instead of silently capping around 52W. Also sets EPP,
disables C3 (its ~1ms exit latency causes input stutter in games), re-arms the
turbo-ratio MSR (0x1AD) to the platform's real per-core-group ceiling, and (boot
only) sets THP to `madvise`, shmem THP to `advise`, and sets up zram swap as a
fallback in case OpenRC's own zram-init lost its startup race.

Must run as root (writes to `/sys`, restarts OpenRC services, writes MSRs). Paths
to `/etc/conf.d/sustained-turbo`, `/etc/throttled.conf`, and the desktop user's
`noctalia` config are hardcoded for this specific machine — adapt before reuse
elsewhere.
