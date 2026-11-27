# 16 — Вимкнення пропрієтарного autostart у відкритому boot

## Проблема (runtime-proven)

Поточний boot із `wsm_open_driver=1` успішно завантажує Nouveau/NVK, але
 userspace autostart `/etc/xdg/autostart/nvidia-settings-autostart.desktop`
 виконує `sh -c '/usr/bin/nvidia-settings --load-config-only'`. Це призводить до:

- `nvidia: loading out-of-tree module taints kernel`;
- `module verification failed: signature and/or required key missing`;
- трьох спроб `nvidia-nvlink` із `NVRM: GPU 0000:01:00.0 is already bound to nouveau`
  і `NVRM: No NVIDIA devices probed`;
- `ERROR: NVIDIA driver is not loaded`, `status=1/FAILURE` для autostart-юніту;
- повторів на `+946s`/`+950s` у журналі.

Cmdline blacklist не завадив явному `modprobe` з боку `nvidia-settings`.

## Фікс (застосовано, user-scope)

Створено drop-in лише для користувача `agents`:

```text
/home/agents/.config/systemd/user/app-nvidia\x2dsettings\x2dautostart@autostart.service.d/override.conf
```

Вміст:

```ini
[Unit]
ConditionKernelCommandLine=!wsm_open_driver=1
```

Логіка: у відкритому boot (`wsm_open_driver=1` присутній) юніт пропускається;
у звичайному NVIDIA-дефолті параметра немає — autostart лишається активним.
Не змінено `/etc/xdg`, GRUB, драйвери, firmware чи глобальні systemd-настройки.

## Перевірка (runtime-proven)

Після `systemctl --user daemon-reload`:

```text
ConditionKernelCommandLine=!wsm_open_driver=1
ConditionResult=no
ActiveState=inactive
SubState=dead
```

`systemctl --user start ...` не запустив `nvidia-settings`; у `dmesg` не з’явилось
нових `NVRM`/`nvidia-nvlink` записів, а `lsmod` не показує активного `nvidia*`.
`nouveau` лишається активним.

## Межі

- Поточний boot лишається tainted (`/proc/sys/kernel/tainted = 12289`) через
  вже виконані до фіксу спроби; чистого стану треба reboot у відкритий boot.
- Фікс діє тільки для користувача `agents`; інші користувачі не змінені.
- `pmu: firmware unavailable`, BIT-table warnings і journald corruption не
  виправлялись — вони не є причиною nvlink/NVRM-помилок.
- Push/PR/tag/release не робився.
