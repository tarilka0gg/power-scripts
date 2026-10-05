#!/bin/bash
# package.sh - pack power-scripts: dist/power-scripts-<version>.tar.gz (+ .sha256).
# Shell scripts, no build step. Installs to the paths the scripts hard-code (/usr/local/bin, /etc/conf.d,
# /etc/local.d, /etc/udev/rules.d, /usr/lib/elogind/system-sleep) and enables nothing: see POST-INSTALL.txt.
# These scripts are written for one machine (HP Victus 16, EC platform_profile, MSR 0x1AD, ACAD supply): read
# README.md before installing on anything else.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME=power-scripts
VERSION=${VERSION:-0.1.0+git$(git rev-parse --short HEAD 2>/dev/null || echo local)}
D=dist/$NAME-$VERSION
rm -rf "${D:?}"

install -Dm755 idle-on.sh idle-off.sh idle-measure.sh battery-powersave-on.sh battery-powersave-off.sh sustained-turbo -t "$D/prefix/bin"
install -Dm755 sustained-turbo.initd "$D/etc/init.d/sustained-turbo"
install -Dm644 sustained-turbo.conf "$D/etc/conf.d/sustained-turbo"
install -Dm644 sustained-turbo-idle.conf "$D/etc/conf.d/sustained-turbo-idle.conf"
install -Dm644 battery-powersave.udev "$D/etc/udev/rules.d/99-battery-powersave.rules"
install -Dm755 performance.start "$D/etc/local.d/performance.start"
install -Dm755 zy-battery.start "$D/etc/local.d/zy-battery.start"
install -Dm755 90-power-limits-rearm "$D/usr/lib/elogind/system-sleep/90-power-limits-rearm"
install -Dm644 README.md -t "$D/prefix/share/doc/$NAME"
echo /usr/local > "$D/REQUIRE_PREFIX"
install -m755 packaging/install.sh "$D/install.sh"
cat > "$D/POST-INSTALL.txt" <<'TXT'
Nothing is enabled. These scripts are tuned to one laptop (HP Victus 16, i7-14650HX + RTX 4070); they write to
/sys/firmware/acpi/platform_profile, the turbo-ratio MSR 0x1AD, CPU/EPP and USB power state. Read the README first.
  rc-update add sustained-turbo default && rc-service sustained-turbo start     the fan/turbo daemon
  udevadm control --reload                                                      AC/battery switching (udev rule)
/etc/local.d/*.start run at boot (the `local` service); the elogind hook runs on resume.
TXT

OUT=dist/$NAME-$VERSION.tar.gz
tar -C dist --owner=0 --group=0 -czf "$OUT" "$NAME-$VERSION"
(cd dist && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
echo "$OUT"
