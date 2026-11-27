#!/usr/bin/env bash
# install-grub-open-driver-choice.sh — додає окремий пункт GRUB для відкритого
# драйвера (nouveau + NVK), лишаючи NVIDIA за замовчуванням.
#
# НЕ чіпає /etc/modprobe.d і НЕ викликає update-initramfs.
# Потрібен root: sudo bash scripts/install-grub-open-driver-choice.sh
# Попередній перегляд без змін і без root: DRY_RUN=1 bash scripts/...
set -euo pipefail

fail() { echo "GRUB-CHOICE-INSTALL-FAIL: $*" >&2; exit 1; }
step() { printf '== %s\n' "$*"; }

KVER="${KVER:-$(uname -r)}"
ROOT_UUID="${ROOT_UUID:-$(sed -nE 's/.*root=UUID=([0-9a-fA-F-]+).*/\1/p' /proc/cmdline | head -n1)}"
CUSTOM="${GRUB_CUSTOM:-/etc/grub.d/40_custom}"
UNIT="${WSM_UNIT:-/etc/systemd/system/wsm-open-driver.service}"
BDF="${BOOT_BDF:-0000:01:00.0}"

BEGIN='# WSM-OPEN-DRIVER-BEGIN'
END='# WSM-OPEN-DRIVER-END'

[ -n "$ROOT_UUID" ] || fail 'не вдалося визначити root UUID з /proc/cmdline'
[ -r "/boot/vmlinuz-$KVER" ] || fail "нема /boot/vmlinuz-$KVER"
[ -r "/boot/initrd.img-$KVER" ] || fail "нема /boot/initrd.img-$KVER"
grep -q '^GRUB_DEFAULT=0' /etc/default/grub 2>/dev/null \
  || fail 'GRUB_DEFAULT не 0 — не можу гарантувати, що nvidia лишиться дефолтом'

build_grub_entry() {
  cat <<EOF
$BEGIN
menuentry 'Kali GNU/Linux (WSM open driver: nouveau + NVK trace)' --class gnu-linux --class gnu --class os {
	insmod part_gpt
	insmod ext2
	search --no-floppy --fs-uuid --set=root $ROOT_UUID
	linux	/boot/vmlinuz-$KVER root=UUID=$ROOT_UUID ro quiet \\
		modprobe.blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm \\
		blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm \\
		nouveau.debug=TOP=trace,FIFO=debug \\
		wsm_open_driver=1
	initrd	/boot/initrd.img-$KVER
}
$END
EOF
}

build_unit() {
  cat <<'EOF'
[Unit]
Description=Load Nouveau only for the WSM open-driver boot
# Пропрієтарні blacklist-файли залишаються недоторканими; явний modprobe
# обходить blacklist тільки тоді, коли GRUB передав маркер wsm_open_driver=1.
ConditionKernelCommandLine=wsm_open_driver=1
After=systemd-modules-load.service
Before=display-manager.service
Before=graphical.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/modprobe nouveau

[Install]
WantedBy=multi-user.target
EOF
}

if [ "${DRY_RUN:-0}" = 1 ]; then
  echo '--- /etc/grub.d/40_custom (append) ---'
  build_grub_entry
  echo '--- wsm-open-driver.service ---'
  build_unit
  echo 'DRY-RUN-OK changes=none'
  exit 0
fi

[ "$(id -u)" -eq 0 ] || fail 'потрібен root: sudo bash scripts/install-grub-open-driver-choice.sh'

backup() {
  [ -e "$1" ] && cp -a "$1" "$1.bak.$(date +%Y%m%d%H%M%S)" || true
}

step 'backup before any write'
backup "$CUSTOM"
backup "$UNIT"

step 'append GRUB entry (idempotent)'
if [ -e "$CUSTOM" ] && grep -q "$BEGIN" "$CUSTOM"; then
  echo 'GRUB-ENTRY-ALREADY-PRESENT'
else
  if [ ! -e "$CUSTOM" ]; then
    printf '#!/bin/sh\nexec tail -n +3 $0\n' >"$CUSTOM"
  fi
  build_grub_entry >>"$CUSTOM"
  chmod 755 "$CUSTOM"
  echo 'GRUB-ENTRY-ADDED'
fi

step 'install conditional systemd unit'
build_unit >"$UNIT"
chmod 644 "$UNIT"

step 'enable unit (does not start it now)'
systemctl enable wsm-open-driver.service >/dev/null

step 'regenerate grub.cfg (no update-initramfs)'
update-grub >/dev/null

step 'verify invariants'
grep -q "$BEGIN" "$CUSTOM" || fail 'маркер GRUB-entries зник'
grep -q 'wsm_open_driver=1' /boot/grub/grub.cfg || fail 'маркера немає в grub.cfg'
grep -q '^GRUB_DEFAULT=0' /etc/default/grub || fail 'GRUB_DEFAULT змінено'
[ "$(systemctl is-enabled wsm-open-driver.service)" = enabled ] \
  || fail 'юніт не увімкнено'
if grep -Rqs '^[[:space:]]*options[[:space:]]\+nouveau' /etc/modprobe.d/; then
  echo 'NOTE: є options nouveau в /etc/modprobe.d (не змінювалось)'
fi

echo "GRUB-CHOICE-INSTALL-OK default=nvidia open-entry='WSM open driver: nouveau + NVK trace' kver=$KVER bdf=$BDF"
echo 'Наступний крок: перезавантажитися, у меню вибрати WSM open driver, потім:'
echo '  bash scripts/capture-nouveau-boot-witness.sh'
