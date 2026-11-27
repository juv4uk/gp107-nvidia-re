# 32 — Free Pascal як основна мова capability-identity зрізу

Free Pascal є primary research implementation; C11 лишається reference для
байтової й поведінкової сумісності. Це userspace sysfs identity/ledger, не
kernel driver, не RM ABI і не дозвіл на доступ до BAR0.

## 1. Реалізація

| Файл | Призначення |
|---|---|
| `pascal/gp107_identity.pas` | FAIL-CLOSED PCI/sysfs inventory, driver-link classification, layout checks |
| `pascal/gp107_mmio.pas` | opt-in, identity, binding, BAR0-space/size та offset gates; далі fail-closed `read-safe-offset-unproven` |
| `pascal/gp107_capabilities.pas` | machine-readable ledger, byte-identical до C |
| `pascal/gp107ctl.pas` | CLI `inventory`, `mmio-read`, `capabilities`, `layout` |
| `pascal/Makefile` | FPC 3.2.2 pinned build |
| `scripts/test-capability-driver.sh` | synthetic identity/binding/ledger/negative gates та C/Pascal parity |

Збірка: `make -C pascal gp107ctl-pascal`. Компілятор перевіряється через
`make -C pascal check-fpc`: очікується точно `3.2.2`.

`Load32Asm` лишився ізольованим reference leaf для статичної перевірки
інструкції `mov eax,[rdi]` + `lfence`. `Read32` ніколи його не викликає.

## 2. Статуси доказів

| Факт | Статус | Межа |
|---|---|---|
| FPC 3.2.2 компілює primary slice | **statically proven** | точний compiler pin і compile-time layout |
| C/Pascal inventory та ledger збігаються | **synthetic-fixture** | це не апаратна сертифікація |
| C/Pascal `mmio-read` однаково відмовляють для valid-looking offset | **synthetic-fixture** | `read-safe-offset-unproven`; жодного resource0 open або BAR mapping |
| `Load32Asm` + `lfence` присутній у Pascal бінарнику | **statically proven** | `objdump`; leaf не використовується public API |
| безпечний GP107 BAR0 offset | **UNPROVEN** | немає підтвердженого register contract |
| BOOT0 та фізичний MMIO | **UNPROVEN / NOT AUTHORIZED / NOT RUN** | ніякого unbind, mapping, aperture read або reboot |

## 3. Safety contract

- Після opt-in та всіх identity/BAR/offset checks API повертає
  `MMIO-FAIL step=read-safe-offset-unproven code=21`.
- Capability ledger не має `granted` стану: unbound + opt-in лишається
  `deferred` із причиною `read-safe-offset-unproven`.
- У Pascal MMIO unit немає `FpOpen`, `FpMMap` або `FpMunmap`; C unit не
  має `openat`, `mmap` чи `munmap`.
- Жодного physical MMIO, driver unbind, Nouveau boot, firmware, UVM/RM ioctl,
  GPU channel/submit чи reboot.

Підсумковий gate marker:
`CAPABILITY-DRIVER-GATE-OK c11=yes fpc=3.2.2 layout=32/68/140 fail-closed=passed mmio=deferred safe-offset=unproven pascal=C-parity hardware-mmio=NOT-AUTHORIZED/NOT-RUN`.
