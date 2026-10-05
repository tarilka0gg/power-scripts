# Packaging

`packaging/package.sh` → `dist/power-scripts-<version>.tar.gz` (+ `.sha256`). Shell scripts for one laptop (HP Victus 16); they write EC/MSR/CPU state, so read README.md first. Installs to the paths the scripts hard-code (`/usr/local/bin`, `/etc/conf.d`, `/etc/local.d`, `/etc/udev/rules.d`, `/usr/lib/elogind/system-sleep`); `PREFIX` must stay `/usr/local`. Enables nothing. No ebuild (by choice).

Install from the tarball: `./install.sh` (under `/usr/local`), `DESTDIR=… ./install.sh` to stage, `./install.sh uninstall` to remove
what it installed (it records a manifest). Existing files in `/etc` are never overwritten; the new copy is written as `<name>.new`.
Checked: install/uninstall in a DESTDIR and the PREFIX guard. The scripts themselves were not run.
